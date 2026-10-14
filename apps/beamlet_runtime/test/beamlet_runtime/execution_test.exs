defmodule BeamletRuntime.ExecutionTest do
  use ExUnit.Case, async: false
  alias Beamlet.{Definition, Identity, Report, Value}
  alias Beamlet.Report.Source
  alias BeamletRuntime.{Coordinator, Scheduler, Worker}
  alias BeamletRuntime.Storage.{Commit, SQLite}
  alias Ecto.Adapters.SQL

  defmodule Fixture do
    @behaviour BeamletRuntime.Handler
    @impl true
    def identity(config), do: Map.get(config, :release, "fixture.v1")
    @impl true
    def operations(_config), do: ["fixture.v1"]
    @impl true
    def validate_input(_definition, %{invalid_schema_reply: true}), do: {:ok, :invalid}

    def validate_input(definition, _config) do
      if is_integer(definition.input) and
           definition.constraints in [%{}, %{"account" => "fixture"}],
         do: :ok,
         else: {:error, :invalid_fixture_input}
    end

    @impl true
    def bind(intent, execution, environment, config) do
      binding = %{
        "handler" => identity(config),
        "operation" => "fixture.v1",
        "protocol" => Map.get(config, :protocol, "fixture.invoke.v1"),
        "resource" => %{"account" => "fixture"},
        "completion" => %{"correlation" => execution.id, "provider" => "fixture"},
        "query" => %{"lookup" => execution.id, "provider" => "fixture"}
      }

      binding =
        if config[:idempotent],
          do:
            Map.put(binding, "idempotency", %{
              "protocol" => "fixture.dedup.v1",
              "key" => intent.id,
              "scope" => %{"collection" => intent.identity.collection},
              "valid_through" => config[:valid_through],
              "expiry_enforced" => true
            }),
          else: binding

      binding = Map.drop(binding, Map.get(config, :omit_capabilities, []))
      with :ok <- validate_binding(intent, binding, environment, config), do: {:ok, binding}
    end

    @impl true
    def validate_binding(intent, binding, environment, config) do
      available = current_resource(config)

      if available and environment["fixture"] == true and
           binding["resource"] == %{"account" => "fixture"} and
           binding["handler"] == identity(config),
         do: validate_input(intent.definition, config),
         else: {:error, :resource_unavailable}
    end

    defp current_resource(%{lose_resource_after_check: true} = config) do
      Agent.get_and_update(config.agent, fn state ->
        count = Map.get(state, :resource_checks, 0)
        {state.available and count == 0, Map.put(state, :resource_checks, count + 1)}
      end)
    end

    defp current_resource(config), do: Agent.get(config.agent, & &1.available)

    @impl true
    def validate_result("fixture.v1", kind, body, _config) do
      valid =
        case kind do
          kind when kind in [:success, :failure] -> is_integer(body)
          :pending -> is_map(body) and is_binary(body["ticket"])
          kind when kind in [:not_found, :not_executed] -> is_nil(body)
        end

      if valid, do: Value.validate(body), else: {:error, :invalid_fixture_result}
    end

    @impl true
    def invoke(grant, config) do
      {:ok, facts} = SQLite.read(config.repo, grant.token.collection, grant.token.intent_id)
      execution = facts.intent.executions[grant.token.execution_id]

      {mode, owner} =
        Agent.get_and_update(config.agent, fn state ->
          record = %{token: grant.token, binding: execution.binding, phase: execution.phase}
          {{state.mode, state.owner}, %{state | invocations: state.invocations ++ [record]}}
        end)

      send(owner, {:invoked, self(), grant})

      case mode do
        :success ->
          {:success, grant.intent.definition.input}

        :failure ->
          {:failure, -1}

        :uncertain ->
          {:uncertain, :connection_lost}

        :raise ->
          raise "external error is not Failure"

        :invalid ->
          {:success, "wrong schema"}

        :pending ->
          {:pending, %{"ticket" => grant.token.execution_id}}

        :block ->
          receive do
            {:finish, result} -> result
          end

        :early_callback ->
          raw =
            signed(
              "early",
              :success,
              42,
              {grant.token.collection, grant.intent.id, grant.token.execution_id}
            )

          {:ok, _stored} =
            Coordinator.callback(
              config.coordinator.(),
              grant.intent.id,
              grant.token.execution_id,
              raw,
              :fixture
            )

          {:pending, %{"ticket" => grant.token.execution_id}}
      end
    end

    @impl true
    def query(intent, execution, config) do
      case Agent.get(config.agent, &Map.get(&1, :query_behavior)) do
        :raise -> raise "provider unavailable"
        :invalid -> {:ok, :not_a_report}
        _normal -> query_report(intent, execution, config)
      end
    end

    defp query_report(intent, execution, config) do
      {kind, body, report_id} =
        Agent.get(config.agent, fn state ->
          {kind, body} = state.query
          {kind, body, Map.get(state, :query_id, "query-result")}
        end)

      source = %Source{
        kind: :query,
        collection: intent.identity.collection,
        intent_id: intent.id,
        execution_id: execution.id,
        binding: execution.binding["query"]
      }

      {:ok,
       %Report{
         id: report_id,
         source: source,
         operation: "fixture.v1",
         kind: kind,
         body: body
       }}
    end

    @impl true
    def verify_callback(intent, execution, {raw, :fixture}, _config) do
      {id, kind, body, scope, signature} = raw
      expected = {intent.identity.collection, intent.id, execution.id}

      cond do
        scope != expected -> {:error, :callback_scope_mismatch}
        signature != signature(id, kind, body, scope) -> {:error, :invalid_signature}
        true -> callback_report(intent, execution, id, kind, body)
      end
    end

    def verify_callback(_intent, _execution, _request, _config), do: {:error, :invalid_provider}

    defp callback_report(intent, execution, id, kind, body) do
      source = %Source{
        kind: :callback,
        collection: intent.identity.collection,
        intent_id: intent.id,
        execution_id: execution.id,
        binding: execution.binding["completion"]
      }

      {:ok, %Report{id: id, source: source, operation: "fixture.v1", kind: kind, body: body}}
    end

    def signed(id, kind, body, scope),
      do: {id, kind, body, scope, signature(id, kind, body, scope)}

    defp signature(id, kind, body, scope),
      do:
        :crypto.mac(
          :hmac,
          :sha256,
          "test-only-key",
          Jason.encode!([id, kind, body, Tuple.to_list(scope), "fixture"])
        )
  end

  setup do
    directory =
      Path.join(System.tmp_dir!(), "beamlet-execution-#{System.unique_integer([:positive])}")

    {:ok, repo} = SQLite.start_link(database: Path.join(directory, "ledger.db"), pool_size: 4)
    Process.unlink(repo)
    :ok = SQLite.migrate(repo)
    owner = self()

    agent =
      start_supervised!(
        {Agent,
         fn ->
           %{
             owner: owner,
             available: true,
             mode: :success,
             invocations: [],
             query: {:not_found, nil},
             clock: 0
           }
         end}
      )

    config = %{repo: repo, agent: agent}
    c = coordinator(repo, config)

    on_exit(fn ->
      if Process.alive?(repo), do: Supervisor.stop(repo)
      File.rm_rf!(directory)
    end)

    %{repo: repo, c: c, agent: agent, config: config}
  end

  defp coordinator(repo, config, opts \\ []) do
    Coordinator.new(
      Keyword.merge(
        [
          repo: repo,
          collection: "collection",
          actor: "runtime",
          handlers: [{Fixture, config}],
          ttl: 30_000
        ],
        opts
      )
    )
  end

  defp worker(c, opts \\ []) do
    start_supervised!(
      Supervisor.child_spec(
        {Worker,
         Keyword.merge(
           [
             coordinator: c,
             id: Ecto.UUID.generate(),
             environment: %{"fixture" => true},
             maintenance_interval: 20
           ],
           opts
         )},
        id: make_ref()
      )
    )
  end

  defp submit(c, key \\ "key", policy \\ :stop_on_failure) do
    {:ok, identity} = Identity.new(c.collection, "namespace", key)
    {:ok, definition} = Definition.new(%{operation: "fixture.v1", input: 42, policy: policy})
    assert {:ok, commit} = Coordinator.submit(c, identity, definition)
    commit.facts.intent.id
  end

  defp prepare(c, id) do
    assert {:ok, commit} = Coordinator.prepare(c, id)
    commit.facts.intent.current_execution_id
  end

  defp grant(c, w, id, execution_id) do
    {worker_id, incarnation} = Worker.session(w)

    assert {:ok, %Commit{reply: {:claimed, token}}} =
             Coordinator.claim(c, id, execution_id, worker_id, incarnation, 0)

    assert {:ok, commit} = Coordinator.authorize(c, token, %{"fixture" => true})
    assert {:ok, grant} = Coordinator.grant(commit)
    grant
  end

  defp facts(c, id) do
    {:ok, facts} = Coordinator.read(c, id)
    facts
  end

  defp eventually(fun, attempts \\ 200) do
    result = fun.()

    cond do
      result ->
        result

      attempts == 0 ->
        flunk("condition did not become true")

      true ->
        receive do
        after
          5 -> :ok
        end

        eventually(fun, attempts - 1)
    end
  end

  defp invocations(agent), do: Agent.get(agent, & &1.invocations)
  defp mode(agent, value), do: Agent.update(agent, &%{&1 | mode: value})
  defp outcome(c, id), do: facts(c, id).intent.outcome

  test "no notification is needed for Submit -> scan -> committed grant -> invoke -> Outcome", %{
    c: c,
    agent: agent
  } do
    id = submit(c)
    w = worker(c)
    assert {:ok, _page} = Scheduler.scan_once(c, [w])
    eventually(fn -> outcome(c, id) end)
    assert %{kind: :succeeded, value: 42} = outcome(c, id)
    assert [%{phase: :start_authorized, token: token, binding: binding}] = invocations(agent)
    execution = facts(c, id).intent.executions[token.execution_id]
    assert execution.authorization == token
    assert execution.binding == binding
    assert {:ok, []} = Coordinator.discover(c)
  end

  test "duplicate concurrent dispatch and grant delivery invoke only once", %{c: c, agent: agent} do
    mode(agent, :block)
    id = submit(c)
    e = prepare(c, id)
    w = worker(c)

    results =
      [Task.async(fn -> Worker.run(w, id, e) end), Task.async(fn -> Worker.run(w, id, e) end)]
      |> Task.await_many()

    assert Enum.sort(results) == Enum.sort([:started, :already_started])
    assert_receive {:invoked, task, grant}
    assert :already_started = Worker.deliver(w, grant)
    send(task, {:finish, {:success, 42}})
    eventually(fn -> outcome(c, id) end)
    assert length(invocations(agent)) == 1
  end

  test "lost authorization reply recovers original grant in same incarnation", %{
    c: c,
    agent: agent
  } do
    id = submit(c)
    e = prepare(c, id)
    w = worker(c)
    original = grant(c, w, id, e)
    assert :started = Worker.run(w, id, e)
    eventually(fn -> outcome(c, id) end)
    assert [%{token: token, binding: binding}] = invocations(agent)
    assert token == original.token
    assert binding == original.binding
  end

  test "restart creates a fresh incarnation and rejects old grant", %{c: c, agent: agent} do
    id = submit(c)
    e = prepare(c, id)
    w = worker(c, id: "worker")
    old = grant(c, w, id, e)
    GenServer.stop(w)
    fresh = worker(c, id: "worker")
    assert {"worker", incarnation} = Worker.session(fresh)
    refute incarnation == old.token.incarnation
    assert {:error, :foreign_incarnation} = Worker.deliver(fresh, old)
    assert {:error, :foreign_incarnation} = Worker.run(fresh, id, e)
    assert invocations(agent) == []
    assert facts(c, id).intent.phase == :open
  end

  test "new incarnation reclaims an expired unstarted Prepared attempt", %{
    c: c,
    agent: agent,
    repo: repo
  } do
    id = submit(c)
    e = prepare(c, id)

    assert {:ok, _commit} =
             SQLite.command(repo, c.collection, id, {:claim, e, "old", "old-inc", 0, 1}, c.actor)

    eventually(fn -> match?({:ok, _}, Coordinator.expire(c, id, e)) end)
    w = worker(c)
    assert {:ok, _page} = Scheduler.scan_once(c, [w])
    eventually(fn -> outcome(c, id) end)
    assert [%{token: %{generation: 2}}] = invocations(agent)
    assert map_size(facts(c, id).intent.executions) == 1
  end

  test "Handler crash, uncertain response and invalid schema never manufacture Failed", %{
    c: c,
    agent: agent
  } do
    w = worker(c)

    for behavior <- [:raise, :uncertain, :invalid] do
      mode(agent, behavior)
      id = submit(c, Atom.to_string(behavior))
      e = prepare(c, id)
      assert :started = Worker.run(w, id, e)
      assert_receive {:invoked, _task, _grant}
      eventually(fn -> map_size(:sys.get_state(w).tasks) == 0 end)
      assert outcome(c, id) == nil
      assert :already_started = Worker.run(w, id, e)
    end

    assert length(invocations(agent)) == 3
  end

  test "explicit qualified Failure obeys StopOnFailure", %{c: c, agent: agent} do
    mode(agent, :failure)
    id = submit(c)
    w = worker(c)
    assert {:ok, _page} = Scheduler.scan_once(c, [w])
    eventually(fn -> outcome(c, id) end)
    assert %{kind: :failed, value: -1} = outcome(c, id)
  end

  test "missing compatible Handler preserves Prepared and later registration makes progress", %{
    c: c,
    agent: agent
  } do
    id = submit(c)
    absent = %{c | handlers: []}
    w = worker(absent)
    assert {:ok, _page} = Scheduler.scan_once(absent, [w])

    assert facts(c, id).intent.executions[facts(c, id).intent.current_execution_id].phase ==
             :prepared

    assert invocations(agent) == []
    assert {:ok, _page} = Scheduler.scan_once(c, [worker(c)])
    eventually(fn -> outcome(c, id) end)
  end

  test "resource mismatch is checked before claiming and a matching Worker can run", %{
    c: c,
    agent: agent
  } do
    id = submit(c)
    wrong = worker(c, environment: %{"fixture" => false})
    right = worker(c)
    assert {:ok, _page} = Scheduler.scan_once(c, [wrong, right])
    eventually(fn -> outcome(c, id) end)
    {right_id, _incarnation} = Worker.session(right)
    assert [%{token: %{worker: ^right_id}}] = invocations(agent)
  end

  test "resource changes after authorization are checked before invocation", %{c: c, agent: agent} do
    id = submit(c)
    e = prepare(c, id)
    w = worker(c)
    g = grant(c, w, id, e)
    Agent.update(agent, &%{&1 | available: false})
    assert {:error, :resource_unavailable} = Worker.deliver(w, g)
    assert invocations(agent) == []
    Agent.update(agent, &%{&1 | available: true})
    assert :started = Worker.deliver(w, g)
    eventually(fn -> outcome(c, id) end)
  end

  test "Pending survives Worker loss and authenticated callback completes independently", %{
    c: c,
    agent: agent
  } do
    mode(agent, :pending)
    id = submit(c)
    e = prepare(c, id)
    w = worker(c)
    assert :started = Worker.run(w, id, e)
    eventually(fn -> facts(c, id).intent.executions[e].phase == :waiting end)
    GenServer.stop(w)
    fresh = coordinator(c.repo, hd(c.handlers) |> elem(1))
    raw = Fixture.signed("event-1", :success, 7, {c.collection, id, e})
    assert {:ok, commit} = Coordinator.callback(fresh, id, e, raw, :fixture)
    assert commit.facts.intent.outcome.value == 7
    revision = commit.facts.revision
    assert {:ok, replay} = Coordinator.callback(fresh, id, e, raw, :fixture)
    assert replay.facts.revision == revision
    assert replay.events == []
    assert length(invocations(agent)) == 1
  end

  test "invalid callback signature or provider never enters the ledger", %{c: c, agent: agent} do
    mode(agent, :pending)
    id = submit(c)
    e = prepare(c, id)
    assert :started = Worker.run(worker(c), id, e)
    eventually(fn -> facts(c, id).intent.executions[e].phase == :waiting end)
    revision = facts(c, id).revision

    assert {:error, :invalid_signature} =
             Coordinator.callback(
               c,
               id,
               e,
               {"event", :success, 5, {c.collection, id, e}, "bad"},
               :fixture
             )

    assert {:error, :invalid_provider} =
             Coordinator.callback(
               c,
               id,
               e,
               Fixture.signed("event", :success, 5, {c.collection, id, e}),
               :wrong
             )

    assert facts(c, id).revision == revision
    assert outcome(c, id) == nil
  end

  test "completion before Pending preserves first result and immutable Outcome", %{
    c: c,
    agent: agent,
    config: config
  } do
    mode(agent, :early_callback)
    configured = %{config | repo: c.repo} |> Map.put(:coordinator, fn -> c end)
    active = coordinator(c.repo, configured)
    id = submit(active)
    e = prepare(active, id)
    assert :started = Worker.run(worker(active), id, e)
    eventually(fn -> length(facts(active, id).intent.executions[e].reports) == 2 end)
    assert %{kind: :succeeded, value: 42} = outcome(active, id)
    assert facts(active, id).intent.executions[e].phase == :resolved
  end

  test "reusing a query identity with changed content preserves conflict and Waiting",
       %{c: c, agent: agent} do
    mode(agent, :pending)
    id = submit(c)
    e = prepare(c, id)
    w = worker(c)
    assert :started = Worker.run(w, id, e)
    eventually(fn -> facts(c, id).intent.executions[e].phase == :waiting end)
    assert {:ok, _page} = Scheduler.scan_once(c, [w])
    assert facts(c, id).intent.executions[e].phase == :waiting
    assert outcome(c, id) == nil
    Agent.update(agent, &%{&1 | query: {:success, 8}})
    assert {:ok, _page} = Scheduler.scan_once(c, [w])
    # A changed response needs its own observation identity. Same identity is a conflict.
    assert facts(c, id).intent.executions[e].conflict
    assert outcome(c, id) == nil
    assert length(invocations(agent)) == 1
  end

  test "report SQL failure retains one stable report and retry does not invoke again", %{
    c: c,
    agent: agent,
    repo: repo
  } do
    SQL.query!(
      repo,
      "CREATE TRIGGER block_reports BEFORE INSERT ON beamlet_outcomes BEGIN SELECT RAISE(ABORT,'injected'); END",
      [],
      log: false
    )

    id = submit(c)
    e = prepare(c, id)
    w = worker(c)
    assert :started = Worker.run(w, id, e)
    eventually(fn -> map_size(:sys.get_state(w).reports) == 1 end)
    assert facts(c, id).intent.executions[e].reports == []
    SQL.query!(repo, "DROP TRIGGER block_reports", [], log: false)
    assert :ok = Worker.flush(w)
    eventually(fn -> outcome(c, id) end)
    assert length(facts(c, id).intent.executions[e].reports) == 1
    assert length(invocations(agent)) == 1
  end

  test "same stable submission reuses Outcome without another invocation", %{c: c, agent: agent} do
    id = submit(c)
    w = worker(c)
    assert {:ok, _page} = Scheduler.scan_once(c, [w])
    eventually(fn -> outcome(c, id) end)
    assert submit(c) == id
    assert {:ok, _page} = Scheduler.scan_once(c, [w])
    assert length(invocations(agent)) == 1
  end

  test "new grant scope and old Handler release cannot silently change", %{
    c: c,
    agent: agent,
    config: config
  } do
    id = submit(c)
    e = prepare(c, id)
    w = worker(c)
    g = grant(c, w, id, e)

    assert {:error, :grant_scope_mismatch} =
             Worker.deliver(w, %{g | token: %{g.token | collection: "other"}})

    changed = coordinator(c.repo, Map.put(config, :release, "fixture.v2"))
    other = worker(changed)
    assert {:ok, replay} = Coordinator.authorize(changed, g.token, %{"fixture" => true})
    assert replay.reply == {:authorized, g.token, g.binding}
    assert {:error, :foreign_incarnation} = Worker.deliver(other, g)
    second_id = submit(c, "old-release")
    second_execution = prepare(c, second_id)
    old_release = grant(c, other, second_id, second_execution)
    assert {:error, :handler_unavailable} = Worker.deliver(other, old_release)
    assert invocations(agent) == []
  end

  test "a saved grant may still invoke after logical cancellation, without replacing Cancelled",
       %{c: c, agent: agent} do
    id = submit(c)
    e = prepare(c, id)
    w = worker(c)
    g = grant(c, w, id, e)
    assert {:ok, _commit} = Coordinator.cancel(c, id, "stop")
    assert :started = Worker.deliver(w, g)
    eventually(fn -> length(facts(c, id).intent.executions[e].reports) == 1 end)
    assert outcome(c, id).kind == :cancelled
    assert length(invocations(agent)) == 1
  end

  test "scheduler cursor wraps and a restarted scheduler rediscovers work", %{c: c} do
    ids = for key <- ["a", "b", "c"], do: submit(c, key)
    assert {:ok, page} = Scheduler.scan_once(c, [], "", 2)
    refute page.cursor == ""
    assert {:ok, last} = Scheduler.scan_once(c, [], page.cursor, 2)
    assert last.cursor == ""
    w = worker(c)

    scheduler =
      start_supervised!({Scheduler, coordinator: c, workers: [w], interval: 20, limit: 1})

    eventually(fn -> Enum.all?(ids, &outcome(c, &1)) end)
    GenServer.stop(scheduler)
    extra = submit(c, "later")

    start_supervised!(
      Supervisor.child_spec({Scheduler, coordinator: c, workers: [w], interval: 20},
        id: :restarted_scheduler
      )
    )

    eventually(fn -> outcome(c, extra) end)
  end

  test "scheduler recovers a lost authorization reply without waiting for expiry", %{
    c: c,
    agent: agent
  } do
    id = submit(c)
    e = prepare(c, id)
    w = worker(c)
    original = grant(c, w, id, e)
    assert {:ok, [%{phase: "start_authorized"}]} = Coordinator.discover(c)
    assert {:ok, _page} = Scheduler.scan_once(c, [w])
    eventually(fn -> outcome(c, id) end)
    assert [%{token: token}] = invocations(agent)
    assert token == original.token
  end

  test "NotFound followed by a new authenticated query observation can settle Waiting", %{
    c: c,
    agent: agent
  } do
    mode(agent, :pending)
    id = submit(c)
    e = prepare(c, id)
    w = worker(c)
    assert :started = Worker.run(w, id, e)
    eventually(fn -> facts(c, id).intent.executions[e].phase == :waiting end)
    assert {:ok, _page} = Scheduler.scan_once(c, [w])

    Agent.update(agent, fn state ->
      state |> Map.put(:query, {:success, 8}) |> Map.put(:query_id, "second-observation")
    end)

    assert {:ok, _page} = Scheduler.scan_once(c, [w])
    assert %{kind: :succeeded, value: 8} = outcome(c, id)
    refute facts(c, id).intent.executions[e].conflict
    assert length(invocations(agent)) == 1
  end

  test "safe RetryOnce uses two attempts and preserves original key and scope", %{
    c: c,
    config: config,
    agent: agent
  } do
    mode(agent, :failure)
    active = coordinator(c.repo, Map.put(config, :idempotent, true))
    id = submit(active, "retry", :retry_once)
    w = worker(active)
    assert {:ok, _page} = Scheduler.scan_once(active, [w])

    eventually(fn ->
      facts(active, id).intent.executions[facts(active, id).intent.current_execution_id].phase ==
        :resolved
    end)

    assert outcome(active, id) == nil
    assert {:ok, _page} = Scheduler.scan_once(active, [w])
    eventually(fn -> outcome(active, id) end)
    assert %{kind: :failed} = outcome(active, id)
    assert map_size(facts(active, id).intent.executions) == 2
    assert [first, second] = invocations(agent)
    assert first.token.execution_id != second.token.execution_id
    assert first.binding["idempotency"] == second.binding["idempotency"]
    assert {:ok, _page} = Scheduler.scan_once(active, [w])
    assert length(invocations(agent)) == 2
  end

  test "finite original guarantee is rechecked at invocation and cannot be extended", %{
    c: c,
    config: config,
    agent: agent
  } do
    mode(agent, :failure)
    clock = fn -> Agent.get(agent, & &1.clock) end

    old =
      coordinator(c.repo, Map.merge(config, %{idempotent: true, valid_through: 5}),
        storage_options: [contract_clock: clock]
      )

    id = submit(old, "finite", :retry_once)
    first = prepare(old, id)
    w = worker(old)
    assert :started = Worker.run(w, id, first)
    eventually(fn -> facts(old, id).intent.executions[first].phase == :resolved end)
    assert {:ok, replaced} = Coordinator.recover(old, id)
    second = replaced.facts.intent.current_execution_id

    newer =
      coordinator(c.repo, Map.merge(config, %{idempotent: true, valid_through: 100}),
        storage_options: [contract_clock: clock]
      )

    g = grant(newer, w, id, second)
    assert g.binding["idempotency"]["valid_through"] == 100
    Agent.update(agent, &%{&1 | clock: 6})
    assert {:error, :idempotency_contract_unavailable} = Worker.deliver(w, g)
    assert length(invocations(agent)) == 1
    assert outcome(old, id) == nil
  end

  test "Unknown after expiry never becomes Failed or a second invocation without evidence", %{
    c: c,
    config: config,
    agent: agent
  } do
    mode(agent, :uncertain)
    active = coordinator(c.repo, config, ttl: 100)
    id = submit(active, "unknown", :retry_once)
    e = prepare(active, id)
    w = worker(active, maintenance_interval: 1000)
    assert :started = Worker.run(w, id, e)
    eventually(fn -> match?({:ok, _commit}, Coordinator.expire(active, id, e)) end)
    assert facts(active, id).intent.executions[e].phase == :unknown
    assert {:ok, _page} = Scheduler.scan_once(active, [w])
    assert outcome(active, id) == nil
    assert map_size(facts(active, id).intent.executions) == 1
    assert length(invocations(agent)) == 1
  end

  test "original incarnation can invoke a saved grant after lease expiry", %{
    c: c,
    config: config,
    agent: agent
  } do
    active = coordinator(c.repo, config, ttl: 100)
    id = submit(active)
    e = prepare(active, id)
    w = worker(active)
    g = grant(active, w, id, e)
    eventually(fn -> match?({:ok, _commit}, Coordinator.expire(active, id, e)) end)
    assert facts(active, id).intent.executions[e].phase == :unknown
    assert :started = Worker.deliver(w, g)
    eventually(fn -> outcome(active, id) end)
    assert outcome(active, id).kind == :succeeded
    assert length(invocations(agent)) == 1
  end

  test "Worker crash during external work loses local report but original query can recover", %{
    c: c,
    config: config,
    agent: agent
  } do
    mode(agent, :block)
    active = coordinator(c.repo, config, ttl: 100)
    id = submit(active)
    e = prepare(active, id)
    w = worker(active, id: "crashing", maintenance_interval: 1000)
    assert :started = Worker.run(w, id, e)
    assert_receive {:invoked, task, g}
    GenServer.stop(w)
    fresh = worker(active, id: "crashing")
    assert {:error, :foreign_incarnation} = Worker.deliver(fresh, g)
    send(task, {:finish, {:success, 9}})
    eventually(fn -> not Process.alive?(task) end)
    eventually(fn -> match?({:ok, _commit}, Coordinator.expire(active, id, e)) end)
    assert outcome(active, id) == nil
    Agent.update(agent, &%{&1 | query: {:success, 9}})
    assert {:ok, _page} = Scheduler.scan_once(active, [fresh])
    assert %{kind: :succeeded, value: 9} = outcome(active, id)
    assert length(invocations(agent)) == 1
  end

  test "two Coordinators and Workers racing one Intent create one external call", %{
    c: c,
    agent: agent
  } do
    id = submit(c)
    first = worker(c)
    other = %{c | actor: "second-coordinator"}
    second = worker(other)

    tasks = [
      Task.async(fn -> Scheduler.scan_once(c, [first]) end),
      Task.async(fn -> Scheduler.scan_once(other, [second]) end)
    ]

    assert Enum.all?(Task.await_many(tasks), &match?({:ok, _page}, &1))
    eventually(fn -> outcome(c, id) end)
    assert length(invocations(agent)) == 1
    assert map_size(facts(c, id).intent.executions) == 1
  end

  test "session capacity refuses new work before allocating authorization", %{c: c, agent: agent} do
    w = worker(c, capacity: 1)
    id = submit(c, "first")
    assert {:ok, _page} = Scheduler.scan_once(c, [w])
    eventually(fn -> outcome(c, id) end)
    second = submit(c, "second")
    e = prepare(c, second)
    assert {:error, :session_capacity_exhausted} = Worker.run(w, second, e)
    assert facts(c, second).intent.executions[e].authorization == nil
    assert facts(c, second).intent.executions[e].lease == nil
    assert length(invocations(agent)) == 1
  end

  test "Operation schema and collection are validated before submission", %{c: c, repo: repo} do
    {:ok, identity} = Identity.new(c.collection, "namespace", "bad")
    {:ok, definition} = Definition.new(%{operation: "fixture.v1", input: "invalid"})
    assert {:error, :invalid_fixture_input} = Coordinator.submit(c, identity, definition)
    {:ok, valid} = Definition.new(%{operation: "fixture.v1", input: 42})

    assert {:error, :collection_mismatch} =
             Coordinator.submit(c, %{identity | collection: "other"}, valid)

    assert [[0]] = SQL.query!(repo, "SELECT count(*) FROM beamlet_intents", [], log: false).rows
  end

  test "production Echo Handler completes a real persisted local operation", %{c: c} do
    echo = %{c | handlers: [{BeamletRuntime.Handlers.Echo, %{}}]}
    {:ok, identity} = Identity.new(c.collection, "namespace", "echo")

    {:ok, definition} =
      Definition.new(%{
        operation: "beamlet.echo.v1",
        input: %{"text" => "你好", "value" => [nil, true, 42]}
      })

    assert {:ok, commit} = Coordinator.submit(echo, identity, definition)
    id = commit.facts.intent.id
    w = worker(echo, environment: %{"echo" => true})
    assert {:ok, _page} = Scheduler.scan_once(echo, [w])
    eventually(fn -> outcome(echo, id) end)
    assert outcome(echo, id).value == definition.input
    assert submit_echo_again(echo, identity, definition) == id
  end

  test "malformed callbacks and valid signatures with invalid result schema are rejected", %{c: c} do
    id = submit(c)
    e = prepare(c, id)
    _grant = grant(c, worker(c), id, e)
    revision = facts(c, id).revision
    assert {:error, :adapter_unavailable} = Coordinator.callback(c, id, e, :malformed, :fixture)

    assert {:error, :invalid_fixture_result} =
             Coordinator.callback(
               c,
               id,
               e,
               Fixture.signed("bad-schema", :success, "bad", {c.collection, id, e}),
               :fixture
             )

    assert facts(c, id).revision == revision
    assert outcome(c, id) == nil
  end

  test "Resolved failure is rediscovered and stops after original guarantee expires", %{
    c: c,
    agent: agent,
    config: config
  } do
    mode(agent, :failure)
    clock = fn -> Agent.get(agent, & &1.clock) end

    active =
      coordinator(c.repo, Map.merge(config, %{idempotent: true, valid_through: 5}),
        storage_options: [contract_clock: clock]
      )

    id = submit(active, "stop", :retry_once)
    e = prepare(active, id)
    w = worker(active)
    assert :started = Worker.run(w, id, e)
    eventually(fn -> facts(active, id).intent.executions[e].phase == :resolved end)
    assert outcome(active, id) == nil
    assert {:ok, [%{phase: "resolved"}]} = Coordinator.discover(active)
    Agent.update(agent, &%{&1 | clock: 6})
    assert {:ok, _page} = Scheduler.scan_once(active, [w])
    assert %{kind: :failed, value: -1} = outcome(active, id)
    assert map_size(facts(active, id).intent.executions) == 1
    assert length(invocations(agent)) == 1
  end

  test "a held grant can call while Authority is offline and retain its report until Repo returns",
       %{c: c} do
    database =
      Path.join(System.tmp_dir!(), "beamlet-offline-#{System.unique_integer([:positive])}.db")

    name = BeamletRuntime.ExecutionTest.NamedRepo
    {:ok, named} = SQLite.start_link(database: database, name: name, pool_size: 1)
    Process.unlink(named)
    :ok = SQLite.migrate(name)

    on_exit(fn ->
      if pid = Process.whereis(name), do: Supervisor.stop(pid)
      Enum.each([database, database <> "-wal", database <> "-shm"], &File.rm/1)
    end)

    echo = %{c | repo: name, handlers: [{BeamletRuntime.Handlers.Echo, %{}}]}
    {:ok, identity} = Identity.new(c.collection, "namespace", "offline")
    {:ok, definition} = Definition.new(%{operation: "beamlet.echo.v1", input: 42})
    {:ok, commit} = Coordinator.submit(echo, identity, definition)
    id = commit.facts.intent.id
    e = prepare(echo, id)
    w = worker(echo, environment: %{"echo" => true})
    {worker_id, incarnation} = Worker.session(w)

    {:ok, %Commit{reply: {:claimed, token}}} =
      Coordinator.claim(echo, id, e, worker_id, incarnation, 0)

    {:ok, authorized} = Coordinator.authorize(echo, token, %{"echo" => true})
    {:ok, g} = Coordinator.grant(authorized)
    Supervisor.stop(named)
    assert :started = Worker.deliver(w, g)
    eventually(fn -> Process.alive?(w) and map_size(:sys.get_state(w).reports) == 1 end)
    assert :already_started = Worker.deliver(w, g)
    {:ok, restarted} = SQLite.start_link(database: database, name: name, pool_size: 1)
    Process.unlink(restarted)
    assert :ok = Worker.flush(w)
    eventually(fn -> outcome(echo, id) end)
    assert %{kind: :succeeded, value: 42} = outcome(echo, id)
    assert length(facts(echo, id).intent.executions[e].reports) == 1
  end

  test "query exceptions or invalid replies do not acknowledge evidence or manufacture failure",
       %{c: c, agent: agent} do
    id = submit(c)
    e = prepare(c, id)
    _g = grant(c, worker(c), id, e)
    revision = facts(c, id).revision
    Agent.update(agent, &Map.put(&1, :query_behavior, :raise))
    assert {:error, :adapter_unavailable} = Coordinator.query(c, id, e)
    Agent.update(agent, &Map.put(&1, :query_behavior, :invalid))
    assert {:error, :invalid_adapter_reply} = Coordinator.query(c, id, e)
    assert facts(c, id).revision == revision
    assert outcome(c, id) == nil
  end

  test "stopped unnamed Repo is classified as unavailable", %{c: c, repo: repo} do
    id = submit(c)
    Supervisor.stop(repo)
    assert {:error, %BeamletRuntime.Storage.Error{kind: :unavailable}} = Coordinator.read(c, id)
  end

  test "Worker status redacts Handler configuration and ignores unsupported messages", %{
    c: c,
    config: config
  } do
    secret = "private-handler-credential-do-not-log"
    active = coordinator(c.repo, Map.put(config, :credential, secret))
    w = worker(active)

    logs =
      ExUnit.CaptureLog.capture_log(fn ->
        send(w, {:unhandled, secret})
        assert {:error, :unsupported_request} = GenServer.call(w, {:unsupported, secret})
        assert Process.alive?(w)
      end)

    refute logs =~ secret
    refute inspect(:sys.get_status(w)) =~ secret
  end

  test "authenticated callback cannot be routed into another Intent", %{c: c} do
    first = submit(c, "first")
    second = submit(c, "second")
    first_execution = prepare(c, first)
    second_execution = prepare(c, second)
    w = worker(c)
    _first_grant = grant(c, w, first, first_execution)
    _second_grant = grant(c, w, second, second_execution)
    raw = Fixture.signed("event", :success, 7, {c.collection, first, first_execution})

    assert {:error, :callback_scope_mismatch} =
             Coordinator.callback(c, second, second_execution, raw, :fixture)

    assert outcome(c, second) == nil
    assert {:ok, _commit} = Coordinator.callback(c, first, first_execution, raw, :fixture)
    assert outcome(c, first).value == 7
  end

  test "malformed Handler schema replies cannot masquerade as a durable submission", %{
    c: c,
    config: config,
    repo: repo
  } do
    active = coordinator(c.repo, Map.put(config, :invalid_schema_reply, true))
    {:ok, identity} = Identity.new(c.collection, "namespace", "invalid-validator")
    {:ok, definition} = Definition.new(%{operation: "fixture.v1", input: 42})
    assert {:error, :invalid_handler_reply} = Coordinator.submit(active, identity, definition)
    assert [[0]] = SQL.query!(repo, "SELECT count(*) FROM beamlet_intents", [], log: false).rows
  end

  test "same submission reuses stored definition and Outcome while Handler is absent", %{c: c} do
    id = submit(c)
    absent = %{c | handlers: []}
    assert submit(absent) == id
    assert {:ok, _page} = Scheduler.scan_once(c, [worker(c)])
    eventually(fn -> outcome(c, id) end)
    revision = facts(c, id).revision
    assert submit(absent) == id
    assert facts(c, id).revision == revision
    {:ok, identity} = Identity.new(c.collection, "namespace", "key")
    {:ok, changed} = Definition.new(%{operation: "fixture.v1", input: 43})
    assert {:error, :definition_conflict} = Coordinator.submit(absent, identity, changed)

    assert {:error, :operation_unavailable} =
             Coordinator.submit(absent, %{identity | key: "new"}, changed)
  end

  test "retry authorization skips a release with an incompatible original protocol", %{
    c: c,
    config: config,
    agent: agent
  } do
    mode(agent, :failure)
    original = coordinator(c.repo, Map.put(config, :idempotent, true))
    id = submit(original, "retry-release", :retry_once)
    e = prepare(original, id)
    assert :started = Worker.run(worker(original), id, e)
    eventually(fn -> facts(original, id).intent.executions[e].phase == :resolved end)
    assert {:ok, replaced} = Coordinator.recover(original, id)
    next = replaced.facts.intent.current_execution_id

    incompatible =
      Map.merge(config, %{idempotent: true, release: "incompatible", protocol: "other.invoke.v1"})

    compatible = Map.merge(config, %{idempotent: true, release: "compatible"})
    active = %{original | handlers: [{Fixture, incompatible}, {Fixture, compatible}]}
    mode(agent, :success)
    assert :started = Worker.run(worker(active), id, next)
    eventually(fn -> outcome(active, id) end)
    assert facts(active, id).intent.executions[next].binding["handler"] == "compatible"
    assert outcome(active, id).kind == :succeeded
  end

  test "undeclared query and callback capabilities never invoke their Adapter", %{
    c: c,
    config: config,
    agent: agent
  } do
    active = coordinator(c.repo, Map.put(config, :omit_capabilities, ["query", "completion"]))
    id = submit(active)
    e = prepare(active, id)
    _g = grant(active, worker(active), id, e)
    revision = facts(active, id).revision
    Agent.update(agent, &Map.put(&1, :query_behavior, :raise))
    assert {:error, :query_not_supported} = Coordinator.query(active, id, e)

    assert {:error, :callback_not_supported} =
             Coordinator.callback(active, id, e, :malformed, :fixture)

    assert facts(active, id).revision == revision
  end

  test "resource contract time is rechecked inside the invocation Task, not only before dispatch",
       %{c: c, config: config, agent: agent} do
    mode(agent, :failure)
    stable = fn -> 0 end

    original =
      coordinator(c.repo, Map.merge(config, %{idempotent: true, valid_through: 5}),
        storage_options: [contract_clock: stable]
      )

    id = submit(original, "dispatch-clock", :retry_once)
    e = prepare(original, id)
    assert :started = Worker.run(worker(original), id, e)
    eventually(fn -> facts(original, id).intent.executions[e].phase == :resolved end)
    assert {:ok, replaced} = Coordinator.recover(original, id)
    next = replaced.facts.intent.current_execution_id

    # First read is delivery's check; the next read at actual invocation is beyond the original guarantee.
    clock = fn ->
      Agent.get_and_update(agent, fn state ->
        {if(state.clock == 0, do: 0, else: 6), %{state | clock: state.clock + 1}}
      end)
    end

    active = %{original | storage_options: [contract_clock: clock]}
    w = worker(active)
    g = grant(original, w, id, next)
    mode(agent, :success)
    assert :started = Worker.deliver(w, g)
    eventually(fn -> Agent.get(agent, & &1.clock) >= 2 end)
    assert length(invocations(agent)) == 1
    assert outcome(active, id) == nil
    assert :already_started = Worker.deliver(w, g)
  end

  test "resource changes between Task dispatch and actual call prevent invocation", %{
    c: c,
    config: config,
    agent: agent
  } do
    id = submit(c, "dispatch-resource")
    e = prepare(c, id)
    active = coordinator(c.repo, Map.put(config, :lose_resource_after_check, true))
    w = worker(active)
    g = grant(c, w, id, e)
    assert :started = Worker.deliver(w, g)
    eventually(fn -> Agent.get(agent, &Map.get(&1, :resource_checks, 0)) >= 2 end)
    assert invocations(agent) == []
    assert outcome(c, id) == nil
    assert :already_started = Worker.deliver(w, g)
  end

  test "candidate qualification still commits an expired lease rejection barrier", %{
    c: c,
    config: config,
    agent: agent
  } do
    mode(agent, :failure)
    original = coordinator(c.repo, Map.put(config, :idempotent, true))
    id = submit(original, "expired-selection", :retry_once)
    e = prepare(original, id)
    assert :started = Worker.run(worker(original), id, e)
    eventually(fn -> facts(original, id).intent.executions[e].phase == :resolved end)
    assert {:ok, replaced} = Coordinator.recover(original, id)
    next = replaced.facts.intent.current_execution_id

    incompatible =
      Map.merge(config, %{idempotent: true, release: "incompatible", protocol: "other.invoke.v1"})

    active = %{original | handlers: [{Fixture, incompatible}], ttl: 1}
    {worker_id, incarnation} = Worker.session(worker(active))

    assert {:ok, %Commit{reply: {:claimed, token}}} =
             Coordinator.claim(active, id, next, worker_id, incarnation, 0)

    receive do
    after
      20 -> :ok
    end

    assert {:ok, %Commit{reply: {:rejected, :lease_expired}} = commit} =
             Coordinator.authorize(active, token, %{"fixture" => true})

    assert commit.facts.intent.executions[next].lease.invalidated
    assert commit.facts.intent.executions[next].authorization == nil
    assert commit.events != []
    assert outcome(active, id) == nil
    assert length(invocations(agent)) == 1
  end

  defp submit_echo_again(c, identity, definition) do
    {:ok, commit} = Coordinator.submit(c, identity, definition)
    commit.facts.intent.id
  end
end
