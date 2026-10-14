# A controlled, independent SQL resource used only by the conformance runner.
# Invocation rows are deliberately NOT deduplicated: duplicate effects must be detected.
defmodule Beamlet.TraceFixture do
  @behaviour BeamletRuntime.Handler
  alias Beamlet.Report
  alias Beamlet.Report.Source
  alias Ecto.Adapters.SQL

  def identity(_), do: "trace.fixture.v1"
  def operations(_), do: ["trace.effect.v1"]

  def validate_input(%{operation: "trace.effect.v1", input: input, constraints: constraints}, _)
      when is_integer(input) and constraints == %{}, do: :ok

  def validate_input(_, _), do: {:error, :invalid_trace_input}

  def bind(intent, execution, _environment, config) do
    {:ok, binding(intent, execution.id, config)}
  end

  def validate_binding(intent, binding, _environment, config) do
    execution_id = get_in(binding, ["completion", "execution"])

    if binding == binding(intent, execution_id, config),
      do: :ok,
      else: {:error, :trace_binding_changed}
  end

  def validate_result("trace.effect.v1", kind, body, _)
      when kind in [:success, :failure] and is_integer(body), do: :ok

  def validate_result("trace.effect.v1", :not_found, nil, _), do: :ok
  def validate_result(_, _, _, _), do: {:error, :invalid_trace_result}

  def invoke(grant, config) do
    SQL.query!(config.repo, "INSERT INTO calls (intent, execution, value) VALUES (?, ?, ?)", [
      grant.token.intent_id,
      grant.token.execution_id,
      grant.intent.definition.input
    ])

    send(config.owner, {:trace_invoked, self(), grant})

    receive do
      {:trace_reply, value} -> {:success, value}
    end
  end

  def query(intent, execution, config) do
    body = completed(config.repo, intent.id, execution.id)
    kind = if is_nil(body), do: :not_found, else: :success
    {:ok, report(intent, execution, :query, kind, body)}
  end

  # A local fixture capability; raw callback data is checked against independent SQL.
  def verify_callback(intent, execution, {raw, :trace_local}, config) do
    case completed(config.repo, intent.id, execution.id) do
      value when is_integer(value) and raw == value ->
        {:ok, report(intent, execution, :callback, :success, value)}

      _ ->
        {:error, :unverified_trace_completion}
    end
  end

  def verify_callback(_, _, _, _), do: {:error, :unverified_trace_completion}

  def completed(repo, intent, execution) do
    case SQL.query!(
           repo,
           "SELECT value FROM calls WHERE intent=? AND execution=? AND completed=1",
           [intent, execution]
         ).rows do
      [] -> nil
      [[value]] -> value
      _ -> raise "duplicate invocation escaped the Worker tombstone"
    end
  end

  defp binding(intent, execution, config) do
    %{
      "operation" => intent.definition.operation,
      "handler" => identity(config),
      "protocol" => "trace.invoke.v1",
      "resource" => %{"instance" => config.instance},
      "query" => %{"protocol" => "trace.query.v1", "execution" => execution},
      "completion" => %{"protocol" => "trace.callback.v1", "execution" => execution}
    }
  end

  defp report(intent, execution, source, kind, body) do
    capability = execution.binding[if(source == :callback, do: "completion", else: "query")]

    %Report{
      id: if(kind == :not_found, do: "missing", else: "completion"),
      operation: intent.definition.operation,
      kind: kind,
      body: body,
      source: %Source{
        kind: source,
        collection: intent.identity.collection,
        intent_id: intent.id,
        execution_id: execution.id,
        binding: capability
      }
    }
  end
end

defmodule Beamlet.TraceDriver do
  alias Beamlet.Agent.Caller
  alias Beamlet.Agent.Caller.{Decision, Dependency}
  alias Beamlet.{Definition, Identity, Judgment}
  alias BeamletRuntime.{Coordinator, Worker}
  alias BeamletRuntime.Storage.SQLite
  alias Ecto.Adapters.SQL

  @authority Beamlet.TraceAuthority
  @caller Beamlet.TraceCaller
  def start(directory, stem, profile) do
    base = Path.join(directory, stem)
    authority_path = base <> "-authority.db"
    {:ok, _} = SQLite.start_link(database: authority_path, name: @authority, pool_size: 1)
    :ok = SQLite.migrate(@authority)
    {:ok, observer} = SQLite.start_link(database: authority_path, pool_size: 1)
    {:ok, resource} = SQLite.start_link(database: base <> "-resource.db", pool_size: 1)

    SQL.query!(
      resource,
      "CREATE TABLE calls (id INTEGER PRIMARY KEY, intent TEXT NOT NULL, execution TEXT NOT NULL, value INTEGER NOT NULL, completed INTEGER NOT NULL DEFAULT 0)",
      []
    )

    config = %{owner: self(), repo: resource, instance: Ecto.UUID.generate()}

    c =
      Coordinator.new(
        repo: @authority,
        collection: "trace",
        actor: "fixture",
        handlers: [{Beamlet.TraceFixture, config}],
        ttl: 60_000
      )

    state = %{
      base: base,
      authority_path: authority_path,
      observer: observer,
      resource: resource,
      coordinator: c,
      profile: profile,
      workers: %{},
      sessions: %{},
      invocations: %{},
      id: nil,
      token: nil,
      grant: nil,
      caller: nil
    }

    state = start_worker(state, 1)

    if profile == "caller" do
      {:ok, _} = Caller.start_link(database: base <> "-caller.db", name: @caller, pool_size: 1)
      :ok = Caller.migrate(@caller)
      %{state | caller: Caller.new(@caller, c, "1")}
    else
      state
    end
  end

  def close(state) do
    # The process dictionary is cleanup bookkeeping only, including tasks/Repos
    # created by a driver step that subsequently raises before returning state.
    for pid <- Process.get(:trace_processes, []),
        Process.alive?(pid),
        do: Process.exit(pid, :kill)

    Process.delete(:trace_processes)
    for pid <- Map.values(state.workers), Process.alive?(pid), do: GenServer.stop(pid)

    for repo <- [@caller, @authority],
        pid = Process.whereis(repo),
        not is_nil(pid),
        do: Supervisor.stop(pid)

    for pid <- [state.observer, state.resource], Process.alive?(pid), do: Supervisor.stop(pid)
  end

  def drive(state, op) do
    next = apply_op(state, op)

    actual =
      if state.profile == "worker", do: worker_projection(next), else: caller_projection(next)

    {next, Map.put(actual, "op", op)}
  end

  defp apply_op(%{profile: "worker"} = s, "submit") do
    {:ok, commit} = Coordinator.submit(s.coordinator, identity(1), definition(0))
    %{s | id: commit.facts.intent.id}
  end

  defp apply_op(s, "create") do
    {:ok, _} = SQLite.command(@authority, "trace", s.id, {:create_execution, "1"}, "fixture")
    s
  end

  defp apply_op(s, "claim") do
    {worker, incarnation} = Worker.session(s.workers[1])

    {:ok, %{reply: {:claimed, token}}} =
      Coordinator.claim(s.coordinator, s.id, "1", worker, incarnation, 0)

    %{s | token: token}
  end

  defp apply_op(s, "authorize") do
    {:ok, commit} = Coordinator.authorize(s.coordinator, s.token, %{})
    {:ok, grant} = Coordinator.grant(commit)
    %{s | grant: grant}
  end

  defp apply_op(s, "invoke") do
    :started = Worker.deliver(s.workers[1], s.grant)
    invocation(s, 1)
  end

  defp apply_op(s, "duplicate_grant") do
    :already_started = Worker.deliver(s.workers[1], s.grant)
    s
  end

  defp apply_op(s, "cancel") do
    {:ok, _} = Coordinator.cancel(s.coordinator, s.id, 0)
    s
  end

  defp apply_op(s, "authority_down") do
    Supervisor.stop(Process.whereis(@authority))
    s
  end

  defp apply_op(s, "authority_up") do
    {:ok, _} = SQLite.start_link(database: s.authority_path, name: @authority, pool_size: 1)
    :ok = SQLite.migrate(@authority)
    s
  end

  defp apply_op(s, "worker_down") do
    GenServer.stop(s.workers[1])
    s
  end

  defp apply_op(s, "worker_up") do
    next = start_worker(s, 1)
    {:error, :foreign_incarnation} = Worker.deliver(next.workers[1], s.grant)
    next
  end

  defp apply_op(s, op) when op in ["complete_retained", "complete_lost"] do
    complete(s, 1)
    pid = s.invocations[1].pid

    if Process.alive?(pid) do
      monitor = Process.monitor(pid)
      send(pid, {:trace_reply, 0})

      receive do
        {:DOWN, ^monitor, :process, ^pid, _} -> :ok
      after
        5_000 -> raise "fixture task did not finish"
      end
    end

    if op == "complete_retained", do: :ok = Worker.flush(s.workers[1])
    s
  end

  defp apply_op(s, "flush") do
    :ok = Worker.flush(s.workers[1])
    s
  end

  defp apply_op(s, op) when op in ["query", "duplicate_query"] do
    {:ok, _} = Coordinator.query(s.coordinator, s.id, "1")
    s
  end

  defp apply_op(s, "open") do
    {:ok, _} = Caller.open(s.caller, "sources", [dependency("a", 1, 1), dependency("b", 2, 2)])
    s
  end

  defp apply_op(s, op) when op in ["submit_sources", "collect_a", "collect_sources"] do
    {:ok, _} = Caller.advance(s.caller, "sources")
    s
  end

  defp apply_op(s, "recover_sources") do
    for {id, value} <- [{1, 1}, {2, 2}] do
      {:ok, _} = Coordinator.submit(s.coordinator, identity(id), definition(value))
    end

    {:ok, _} = Caller.advance(s.caller, "sources")
    s
  end

  defp apply_op(s, op) when op in ["start_a", "start_b", "start_c"] do
    logical = %{"start_a" => 1, "start_b" => 2, "start_c" => 3}[op]
    s = if logical == 3, do: start_worker(s, 2), else: s
    intent = intent(s, logical)
    {:ok, _} = SQLite.command(@authority, "trace", intent.id, {:create_execution, "1"}, "fixture")
    :started = Worker.run(s.workers[if(logical == 3, do: 2, else: 1)], intent.id, "1")
    invocation(s, logical)
  end

  defp apply_op(s, op) when op in ["complete_a", "complete_b", "complete_c"] do
    logical = %{"complete_a" => 1, "complete_b" => 2, "complete_c" => 3}[op]
    complete(s, logical)
    i = intent(s, logical)
    {:ok, _} = Coordinator.callback(s.coordinator, i.id, "1", i.definition.input, :trace_local)
    s
  end

  defp apply_op(s, "decide") do
    {:ok, _} =
      Caller.decide(
        s.caller,
        "computation",
        "step",
        [source_round: "sources", source_slot: "a", rule: "1"],
        fn outcome ->
          {:ok,
           %{
             value: outcome.value,
             next_round: "next",
             dependency: dependency("c", 3, outcome.value)
           }}
        end
      )

    s
  end

  defp apply_op(s, "register") do
    {:ok, _} = Caller.register_next(s.caller, "computation", "step")
    s
  end

  defp apply_op(s, "lose_successor_reply") do
    {:ok, decision} = Caller.read_decision(s.caller, "computation", "step")
    {:ok, round} = Caller.read(s.caller, "next")
    [dep] = round.dependencies
    ^dep = decision.dependency
    # Authority commits; the caller never receives/binds the reply.
    {:ok, _} = Coordinator.submit(s.coordinator, dep.identity, dep.definition)
    s
  end

  defp apply_op(s, "caller_down") do
    Supervisor.stop(Process.whereis(@caller))
    s
  end

  defp apply_op(s, "caller_up") do
    {:ok, _} = Caller.start_link(database: s.base <> "-caller.db", name: @caller, pool_size: 1)
    :ok = Caller.migrate(@caller)
    s
  end

  defp apply_op(s, op) when op in ["submit_successor", "collect_c"] do
    {:ok, _} = Caller.advance_next(s.caller, "computation", "step")
    s
  end

  defp apply_op(s, op)
       when op in ["keep_open", "before_manifest", "before_send", "after_restart"], do: s

  defp start_worker(s, id) do
    {:ok, pid} =
      Worker.start_link(
        coordinator: s.coordinator,
        id: to_string(id),
        maintenance_interval: 1_000_000
      )

    Process.unlink(pid)
    remember(pid)
    {_, incarnation} = Worker.session(pid)
    sessions = Map.get(s.sessions, id, [])
    if incarnation in sessions, do: raise("Worker reused an incarnation")

    %{
      s
      | workers: Map.put(s.workers, id, pid),
        sessions: Map.put(s.sessions, id, sessions ++ [incarnation])
    }
  end

  defp invocation(s, logical) do
    receive do
      {:trace_invoked, pid, grant} ->
        expected = if s.profile == "worker", do: s.id, else: intent(s, logical).id
        if grant.token.intent_id != expected, do: raise("invocation crossed Intent scope")
        remember(pid)
        %{s | invocations: Map.put(s.invocations, logical, %{pid: pid, grant: grant})}
    after
      5_000 -> raise "Worker did not invoke the resource"
    end
  end

  defp complete(s, logical) do
    grant = s.invocations[logical].grant

    %{num_rows: 1} =
      SQL.query!(
        s.resource,
        "UPDATE calls SET completed=1 WHERE intent=? AND execution=? AND completed=0",
        [grant.token.intent_id, grant.token.execution_id]
      )
  end

  defp worker_projection(s) do
    {:ok, facts} = SQLite.read(s.observer, "trace", s.id)
    i = facts.intent
    e = i.executions["1"]
    reports = Judgment.reports(i)
    resource = resource(s, i.id)

    Map.merge(resource, %{
      "online" => not is_nil(Process.whereis(@authority)),
      "phase" => text(i.phase),
      "current" => i.current_execution_id || "none",
      "execution" => if(e, do: text(e.phase), else: "absent"),
      "knowledge" => if(e && e.result, do: text(e.result.kind), else: "none"),
      "revision" => i.judgment_revision,
      "reports" => length(reports),
      "workerReports" => Enum.count(reports, &is_nil(&1.source)),
      "queryReports" => Enum.count(reports, &(&1.source && &1.source.kind == :query)),
      "conflictsFree" => Judgment.no_conflicts?(i),
      "outcome" => outcome(i),
      "value" => value(i),
      "workerAlive" => Process.alive?(s.workers[1]),
      "incarnation" => incarnation(s)
    })
  end

  defp caller_projection(s) do
    # Observation connection stays open while the caller service is stopped.
    caller = %{s.caller | repo: caller_observer(s)}
    {:ok, source} = Caller.read(caller, "sources")

    next = optional(Caller.read(caller, "next"), :round_not_found)
    decision = optional(Caller.read_decision(caller, "computation", "step"), :decision_not_found)

    [[catalog]] =
      SQL.query!(s.observer, "SELECT COUNT(*) FROM beamlet_intents WHERE collection=?", ["trace"]).rows

    %{
      "catalog" => catalog,
      "sourceComplete" => not is_nil(source.aggregate),
      "nextExists" => not is_nil(next),
      "nextComplete" => not is_nil(next && next.aggregate),
      "decision" => not is_nil(decision),
      "decisionSound" => decision_sound?(s, source, decision),
      "manifestSound" =>
        is_nil(next) or (not is_nil(decision) and next.dependencies == [decision.dependency]),
      "consumed" => if(decision, do: decision.value, else: -1),
      "nextInput" => if(next, do: hd(next.dependencies).definition.input, else: -1),
      "a" => item(s, 1),
      "b" => item(s, 2),
      "c" => item(s, 3)
    }
  end

  defp optional({:ok, value}, _missing), do: value
  defp optional({:error, missing}, missing), do: nil

  defp incarnation(s) do
    sessions = s.sessions[1]

    current =
      if Process.alive?(s.workers[1]),
        do: elem(Worker.session(s.workers[1]), 1),
        else: List.last(sessions)

    case Enum.find_index(sessions, &(&1 == current)) do
      nil -> raise "unrecognized Worker incarnation"
      index -> index + 1
    end
  end

  defp decision_sound?(_s, _source, nil), do: true

  defp decision_sound?(s, source, decision) do
    original = intent(s, 1)

    expected = %Decision{
      owner: "1",
      collection: "trace",
      computation: "computation",
      key: "step",
      source_round: "sources",
      source_slot: "a",
      rule: "1",
      intent_id: original.id,
      outcome: original.outcome,
      value: original.outcome.value,
      next_round: "next",
      dependency: dependency("c", 3, original.outcome.value)
    }

    decision === expected and decision.outcome === source.outcomes["a"] and
      decision.outcome.kind == :succeeded
  end

  defp caller_observer(s) do
    case Process.get(:trace_caller_observer) do
      nil ->
        {:ok, pid} = Caller.start_link(database: s.base <> "-caller.db", pool_size: 1)
        # Supervisor cleanup below must use a graceful stop for linked Repos.
        Process.put(:trace_caller_observer, pid)
        pid

      pid ->
        pid
    end
  end

  def close_observer do
    if pid = Process.delete(:trace_caller_observer), do: Supervisor.stop(pid)
  end

  defp item(s, logical) do
    case intent(s, logical) do
      nil ->
        %{
          "exists" => false,
          "phase" => "open",
          "execution" => "absent",
          "knowledge" => "none",
          "reports" => 0,
          "callbacks" => 0,
          "outcome" => "none",
          "value" => -1,
          "calls" => 0,
          "finished" => false
        }

      i ->
        e = i.executions["1"]
        reports = Judgment.reports(i)

        Map.merge(resource(s, i.id), %{
          "exists" => true,
          "phase" => text(i.phase),
          "execution" => if(e, do: text(e.phase), else: "absent"),
          "knowledge" => if(e && e.result, do: text(e.result.kind), else: "none"),
          "reports" => length(reports),
          "callbacks" => Enum.count(reports, &(&1.source && &1.source.kind == :callback)),
          "outcome" => outcome(i),
          "value" => value(i)
        })
    end
  end

  defp resource(s, id) do
    [[calls, finished]] =
      SQL.query!(
        s.resource,
        "SELECT COUNT(*), COALESCE(SUM(completed),0) FROM calls WHERE intent=?",
        [id]
      ).rows

    %{"calls" => calls, "finished" => finished > 0}
  end

  defp intent(s, logical) do
    case SQL.query!(
           s.observer,
           "SELECT id FROM beamlet_intents WHERE collection=? AND namespace=? AND submission_key=?",
           ["trace", to_string(logical), "1"]
         ).rows do
      [] ->
        nil

      [[id]] ->
        {:ok, facts} = SQLite.read(s.observer, "trace", id)
        facts.intent
    end
  end

  defp identity(logical) do
    {:ok, identity} = Identity.new("trace", to_string(logical), "1")
    identity
  end

  defp definition(input) do
    {:ok, definition} =
      Definition.new(%{operation: "trace.effect.v1", input: input, policy: :stop_on_failure})

    definition
  end

  defp dependency(slot, logical, input) do
    {:ok, dependency} = Dependency.new(slot, identity(logical), definition(input))
    dependency
  end

  defp outcome(i), do: if(i.outcome, do: text(i.outcome.kind), else: "none")
  defp value(i), do: if(i.outcome, do: i.outcome.value, else: -1)
  defp text(atom), do: Atom.to_string(atom)
  defp remember(pid), do: Process.put(:trace_processes, [pid | Process.get(:trace_processes, [])])
end
