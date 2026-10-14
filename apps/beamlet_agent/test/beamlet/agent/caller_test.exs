defmodule Beamlet.Agent.CallerTest do
  use ExUnit.Case, async: false
  alias Beamlet.Agent.Caller
  alias Beamlet.Agent.Caller.{Dependency, Error}
  alias Beamlet.{Definition, Identity, Value}
  alias BeamletRuntime.Approval.Store, as: ApprovalStore
  alias BeamletRuntime.{Coordinator, Scheduler, Worker}
  alias BeamletRuntime.Handlers.{Approval, Echo}
  alias BeamletRuntime.Storage.SQLite
  alias Ecto.Adapters.SQL

  defmodule Fixture do
    @behaviour BeamletRuntime.Handler
    def identity(_config), do: "caller-fixture.v1"
    def operations(_config), do: ["caller.example.v1"]

    def validate_input(definition, _config) do
      if definition.input in ["failure", "unknown"], do: :ok, else: {:error, :invalid_input}
    end

    def bind(_intent, _execution, _environment, _config), do: {:ok, fixture_binding()}

    def validate_binding(_intent, saved, _environment, _config) do
      if saved == fixture_binding(), do: :ok, else: {:error, :resource_mismatch}
    end

    def validate_result(_operation, _kind, body, _config), do: Value.validate(body)

    def invoke(%{intent: %{definition: %{input: "failure"}}}, _config),
      do: {:failure, %{"error" => "fixture"}}

    def invoke(_grant, _config), do: {:uncertain, :unknown}

    defp fixture_binding,
      do: %{
        "operation" => "caller.example.v1",
        "handler" => "caller-fixture.v1",
        "protocol" => "fixture.v1",
        "resource" => %{"name" => "fixture"}
      }
  end

  setup do
    directory =
      Path.join(System.tmp_dir!(), "beamlet-caller-#{System.unique_integer([:positive])}")

    authority_path = Path.join(directory, "authority.db")
    caller_path = Path.join(directory, "caller.db")
    approval_path = Path.join(directory, "approval.db")
    {_authority_child, authority} = repo(SQLite, authority_path)
    {caller_child, caller_repo} = repo(Caller, caller_path)
    {_resource_child, resource} = repo(ApprovalStore, approval_path)
    :ok = SQLite.migrate(authority)
    :ok = Caller.migrate(caller_repo)
    assert {:ok, :ok} = ApprovalStore.migrate(resource, "approvals")
    service = ApprovalStore.new(resource, "approvals")

    coordinator =
      Coordinator.new(
        repo: authority,
        collection: "collection",
        actor: "local-caller",
        handlers: [{Echo, nil}, {Approval, %{service: service}}, {Fixture, nil}],
        ttl: 50
      )

    caller = Caller.new(caller_repo, coordinator, "agent-1")
    on_exit(fn -> File.rm_rf!(directory) end)

    %{
      caller: caller,
      coordinator: coordinator,
      service: service,
      caller_child: caller_child,
      caller_path: caller_path
    }
  end

  defp repo(module, path) do
    id = make_ref()
    pid = start_supervised!(Supervisor.child_spec({module, database: path, pool_size: 1}, id: id))
    {id, pid}
  end

  defp dependency(
         slot,
         key,
         operation \\ "beamlet.echo.v1",
         input \\ %{"answer" => 42},
         namespace \\ "agent-1"
       ) do
    {:ok, identity} = Identity.new("collection", namespace, key)
    {:ok, definition} = Definition.new(%{operation: operation, input: input})
    {:ok, dependency} = Dependency.new(slot, identity, definition)
    dependency
  end

  defp approval(slot, key),
    do:
      dependency(slot, key, "human.approval.v1", %{
        "service" => "approvals",
        "subject" => slot,
        "responders" => ["reviewer"]
      })

  defp worker(coordinator) do
    start_supervised!(
      Supervisor.child_spec(
        {Worker,
         coordinator: coordinator,
         id: Ecto.UUID.generate(),
         environment: %{"echo" => true, "approval_service" => "approvals"}},
        id: make_ref()
      )
    )
  end

  defp run_round(coordinator, round) do
    w = worker(coordinator)
    assert {:ok, _page} = Scheduler.scan_once(coordinator, [w])

    Enum.each(Enum.uniq(Map.values(round.intents)), fn id ->
      eventually(fn ->
        {:ok, facts} = Coordinator.read(coordinator, id)
        current = facts.intent.executions[facts.intent.current_execution_id]

        current &&
          (current.phase in [:waiting, :resolved] or facts.intent.definition.input == "unknown")
      end)
    end)

    w
  end

  defp eventually(fun, attempts \\ 200) do
    cond do
      fun.() ->
        :ok

      attempts == 0 ->
        flunk("expected persisted progress")

      true ->
        receive do
        after
          5 -> :ok
        end

        eventually(fun, attempts - 1)
    end
  end

  test "manifest is durable before submission and round identity cannot change meaning", %{
    caller: caller,
    coordinator: c,
    caller_child: child,
    caller_path: path
  } do
    a = dependency("a", "1")
    b = dependency("b", "2")
    assert {:ok, opened} = Caller.open(caller, "round", [b, a])
    assert Enum.map(opened.dependencies, & &1.slot) == ["a", "b"]
    assert opened.intents == %{}
    assert {:ok, []} = Coordinator.discover(c)
    stop_supervised!(child)
    {_child, restarted} = repo(Caller, path)
    restored = Caller.new(restarted, c, "agent-1")
    assert {:ok, ^opened} = Caller.read(restored, "round")
    assert {:ok, ^opened} = Caller.open(restored, "round", [a, b])
    assert {:error, :round_definition_conflict} = Caller.open(restored, "round", [a])
    changed = dependency("b", "2", "beamlet.echo.v1", %{"answer" => 43})
    assert {:error, :round_definition_conflict} = Caller.open(restored, "round", [a, changed])
    assert {:ok, []} = Coordinator.discover(c)
  end

  test "all slots persist full committed Outcomes and replay without a new Execution", %{
    caller: caller,
    coordinator: c
  } do
    assert {:ok, _round} =
             Caller.open(caller, "echo", [
               dependency("left", "1"),
               dependency("right", "2", "beamlet.echo.v1", "right")
             ])

    assert {:ok, submitted} = Caller.advance(caller, "echo")
    assert map_size(submitted.intents) == 2
    assert submitted.aggregate == nil
    run_round(c, submitted)
    assert {:ok, completed} = Caller.advance(caller, "echo")
    assert completed.aggregate["left"]["outcome"].value == %{"answer" => 42}
    assert completed.aggregate["right"]["outcome"].value == "right"
    assert {:ok, ^completed} = Caller.advance(caller, "echo")

    for {slot, id} <- completed.intents do
      {:ok, facts} = Coordinator.read(c, id)
      assert completed.aggregate[slot] == %{"intent_id" => id, "outcome" => facts.intent.outcome}
      assert map_size(facts.intent.executions) == 1
    end

    offline = %{caller | coordinator: %{c | repo: :missing_authority}}
    assert {:ok, ^completed} = Caller.advance(offline, "echo")
  end

  test "three original dependencies recover two results without pretending the third is complete",
       %{caller: caller, coordinator: c, service: service, caller_child: child, caller_path: path} do
    manifest = [dependency("a", "1"), dependency("b", "2"), approval("c", "3")]
    assert {:ok, _round} = Caller.open(caller, "three", manifest)
    assert {:ok, submitted} = Caller.advance(caller, "three")
    w = run_round(c, submitted)
    assert {:ok, partial} = Caller.advance(caller, "three")
    assert Map.keys(partial.outcomes) |> Enum.sort() == ["a", "b"]
    assert partial.aggregate == nil
    stop_supervised!(child)
    GenServer.stop(w)
    {_child, restarted} = repo(Caller, path)
    restored = Caller.new(restarted, c, "agent-1")
    assert {:ok, ^partial} = Caller.read(restored, "three")
    assert {:ok, ^partial} = Caller.advance(restored, "three")

    assert {:ok, _decision} =
             ApprovalStore.decide(
               service,
               c.collection,
               submitted.intents["c"],
               "reviewer",
               "approved"
             )

    assert {:ok, _page} = Scheduler.scan_once(c, [worker(c)])
    assert {:ok, completed} = Caller.advance(restored, "three")
    assert map_size(completed.aggregate) == 3
    assert completed.outcomes["a"] == partial.outcomes["a"]
    assert completed.outcomes["b"] == partial.outcomes["b"]
    assert completed.outcomes["c"].value["approval_ref"] == submitted.intents["c"]
  end

  test "accepted submission with lost reply is recovered by the manifest's original identity", %{
    caller: caller,
    coordinator: c
  } do
    d = dependency("slot", "lost-reply")
    assert {:ok, _round} = Caller.open(caller, "lost", [d])
    assert {:ok, accepted} = Coordinator.submit(c, d.identity, d.definition)
    assert {:ok, unsent} = Caller.read(caller, "lost")
    assert unsent.intents == %{}
    assert {:ok, recovered} = Caller.advance(caller, "lost")
    assert recovered.intents["slot"] == accepted.facts.intent.id
    assert {:ok, discovered} = Coordinator.discover(c)
    assert length(discovered) == 1
  end

  test "repeated observation cannot fill another slot; intentional same-Intent slots are explicit",
       %{caller: caller, coordinator: c} do
    assert {:ok, _round} =
             Caller.open(caller, "aliases", [dependency("a", "shared"), dependency("b", "shared")])

    assert {:ok, submitted} = Caller.advance(caller, "aliases")
    assert submitted.intents["a"] == submitted.intents["b"]
    assert {:ok, [_one_intent]} = Coordinator.discover(c)
    run_round(c, submitted)
    assert {:ok, completed} = Caller.advance(caller, "aliases")
    assert map_size(completed.aggregate) == 2
    assert completed.outcomes["a"] == completed.outcomes["b"]
    assert {:ok, ^completed} = Caller.advance(caller, "aliases")
    assert {:ok, []} = Coordinator.discover(c)
  end

  test "Failed and Cancelled are slot results, not implicit sibling cancellation", %{
    caller: caller,
    coordinator: c
  } do
    assert {:ok, _round} =
             Caller.open(caller, "terminal", [
               dependency("error", "error", "caller.example.v1", "failure"),
               approval("cancel", "cancel"),
               approval("waiting", "waiting")
             ])

    assert {:ok, submitted} = Caller.advance(caller, "terminal")
    run_round(c, submitted)
    assert {:ok, _commit} = Coordinator.cancel(c, submitted.intents["cancel"], "caller-request")
    assert {:ok, partial} = Caller.advance(caller, "terminal")
    assert partial.outcomes["error"].kind == :failed
    assert partial.outcomes["cancel"].kind == :cancelled
    assert partial.aggregate == nil
    {:ok, sibling} = Coordinator.read(c, submitted.intents["waiting"])
    assert sibling.intent.phase == :open
    assert sibling.intent.outcome == nil
  end

  test "manifest validation rejects unkeyed, duplicate slots and conflicting shared definitions",
       %{caller: caller} do
    d = dependency("a", "1")

    assert {:error, :invalid_dependency} =
             Caller.open(caller, "bad", [%{d | identity: %{d.identity | key: nil}}])

    assert {:error, :duplicate_slot} = Caller.open(caller, "bad", [d, d])
    changed = dependency("b", "1", "beamlet.echo.v1", "changed")
    assert {:error, :conflicting_dependency_definition} = Caller.open(caller, "bad", [d, changed])
    assert {:error, :invalid_dependency_count} = Caller.open(caller, "bad", [])
    assert {:error, :round_not_found} = Caller.read(caller, "bad")
  end

  test "Unknown stays an unfilled slot after expiry and repeated recovery", %{
    caller: caller,
    coordinator: c
  } do
    assert {:ok, _round} =
             Caller.open(caller, "unknown", [
               dependency("a", "1"),
               dependency("b", "2", "caller.example.v1", "unknown")
             ])

    assert {:ok, submitted} = Caller.advance(caller, "unknown")
    run_round(c, submitted)
    id = submitted.intents["b"]

    eventually(fn ->
      {:ok, facts} = Coordinator.read(c, id)

      case Coordinator.expire(c, id, facts.intent.current_execution_id) do
        {:ok, committed} ->
          committed.facts.intent.executions[facts.intent.current_execution_id].phase == :unknown

        _not_yet ->
          false
      end
    end)

    assert {:ok, partial} = Caller.advance(caller, "unknown")
    assert Map.keys(partial.outcomes) == ["a"]
    assert partial.aggregate == nil
    assert {:ok, ^partial} = Caller.advance(caller, "unknown")
    {:ok, facts} = Coordinator.read(c, id)
    assert facts.intent.outcome == nil
    assert facts.intent.phase == :open
    assert map_size(facts.intent.executions) == 1
  end

  test "independent caller Repos serialize manifest creation and merge progress without loss", %{
    caller: caller,
    coordinator: c,
    caller_path: path
  } do
    {_child, peer_repo} = repo(Caller, path)
    :ok = Caller.migrate(peer_repo)
    peer = Caller.new(peer_repo, c, caller.owner)
    manifest = [dependency("a", "1"), dependency("b", "2")]

    tasks =
      for instance <- [caller, peer, caller, peer],
          do: Task.async(fn -> Caller.open(instance, "concurrent", manifest) end)

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert length(Enum.uniq(results)) == 1

    tasks =
      for instance <- [caller, peer],
          do: Task.async(fn -> Caller.advance(instance, "concurrent") end)

    assert Enum.all?(Enum.map(tasks, &Task.await/1), &match?({:ok, _}, &1))
    assert {:ok, submitted} = Caller.read(caller, "concurrent")
    run_round(c, submitted)

    tasks =
      for instance <- [caller, peer],
          do: Task.async(fn -> Caller.advance(instance, "concurrent") end)

    assert Enum.all?(Enum.map(tasks, &Task.await/1), &match?({:ok, _}, &1))
    assert {:ok, completed} = Caller.read(peer, "concurrent")
    assert map_size(completed.aggregate) == 2

    for {slot, id} <- completed.intents do
      {:ok, facts} = Coordinator.read(c, id)
      assert completed.outcomes[slot] == facts.intent.outcome
      assert map_size(facts.intent.executions) == 1
    end
  end

  test "caller write failure after Authority acceptance replays the original stable identity", %{
    caller: caller,
    coordinator: c
  } do
    assert {:ok, _round} = Caller.open(caller, "write-fault", [dependency("a", "1")])
    SQL.query!(caller.repo, "PRAGMA query_only=ON", [])

    try do
      assert {:error, %Error{stage: :persist, slot: "a", reason: :caller_commit_indeterminate}} =
               Caller.advance(caller, "write-fault")

      assert {:ok, unchanged} = Caller.read(caller, "write-fault")
      assert unchanged.intents == %{}
      assert unchanged.outcomes == %{}
      assert {:ok, [accepted]} = Coordinator.discover(c)
      assert accepted.intent_id != nil
    after
      SQL.query!(caller.repo, "PRAGMA query_only=OFF", [])
    end

    assert {:ok, [accepted]} = Coordinator.discover(c)
    assert {:ok, recovered} = Caller.advance(caller, "write-fault")
    assert recovered.intents["a"] == accepted.intent_id
    run_round(c, recovered)
    assert {:ok, completed} = Caller.advance(caller, "write-fault")
    assert completed.aggregate["a"]["outcome"].kind == :succeeded
  end

  test "owner and collection scope prevent round reuse from aliasing another caller", %{
    caller: caller,
    coordinator: c
  } do
    assert {:ok, first} = Caller.open(caller, "same-round-key", [dependency("a", "1")])
    other = Caller.new(caller.repo, c, "agent-2")

    assert {:ok, second} =
             Caller.open(other, "same-round-key", [
               dependency("a", "1", "beamlet.echo.v1", "other", "agent-2")
             ])

    assert first.owner != second.owner
    assert {:ok, first} = Caller.advance(caller, "same-round-key")
    assert {:ok, second} = Caller.advance(other, "same-round-key")
    assert first.intents["a"] != second.intents["a"]
    foreign = %{caller | coordinator: %{c | collection: "other"}}
    assert {:error, :round_collection_mismatch} = Caller.read(foreign, "same-round-key")
    wrong_scope = dependency("b", "2")
    assert {:error, :invalid_dependency} = Caller.open(foreign, "another", [wrong_scope])
  end

  test "malformed structs are rejected without writing a manifest", %{caller: caller} do
    d = dependency("a", "1")
    assert {:error, :invalid_dependency} = Caller.open(caller, "invalid", [%{d | identity: nil}])

    assert {:error, :invalid_dependency} =
             Caller.open(caller, "invalid", [%{d | definition: %{d.definition | input: self()}}])

    assert {:error, :invalid_round_key} = Caller.open(caller, "", [d])
    assert {:error, :round_not_found} = Caller.advance(caller, "absent")
    assert {:error, :round_not_found} = Caller.read(caller, "invalid")
  end

  test "Authority completion while caller storage is offline is read after restart without new execution",
       %{caller: caller, coordinator: c, caller_child: child, caller_path: path} do
    assert {:ok, _round} = Caller.open(caller, "offline-completion", [dependency("a", "1")])
    assert {:ok, submitted} = Caller.advance(caller, "offline-completion")
    stop_supervised!(child)
    run_round(c, submitted)
    {:ok, finished} = Coordinator.read(c, submitted.intents["a"])
    {_child, restarted} = repo(Caller, path)
    restored = Caller.new(restarted, c, "agent-1")
    assert {:ok, ^submitted} = Caller.read(restored, "offline-completion")
    assert {:ok, completed} = Caller.advance(restored, "offline-completion")
    assert completed.aggregate["a"]["outcome"] == finished.intent.outcome
    assert {:ok, ^finished} = Coordinator.read(c, submitted.intents["a"])
  end

  test "different callers may intentionally share a stable submission identity", %{
    caller: caller,
    coordinator: c
  } do
    shared = dependency("first", "shared", "beamlet.echo.v1", "shared", "common")
    peer = Caller.new(caller.repo, c, "agent-2")
    alias_slot = %{shared | slot: "second"}
    assert {:ok, _round} = Caller.open(caller, "round", [shared])
    assert {:ok, _round} = Caller.open(peer, "round", [alias_slot])
    assert {:ok, first} = Caller.advance(caller, "round")
    assert {:ok, second} = Caller.advance(peer, "round")
    assert first.intents["first"] == second.intents["second"]
    run_round(c, first)
    assert {:ok, first} = Caller.advance(caller, "round")
    assert {:ok, second} = Caller.advance(peer, "round")
    assert first.aggregate["first"] == second.aggregate["second"]
  end

  test "lost acceptance reply replays even when the Handler is no longer deployed", %{
    caller: caller,
    coordinator: c
  } do
    d = dependency("a", "1")
    assert {:ok, _round} = Caller.open(caller, "old", [d])
    assert {:ok, accepted} = Coordinator.submit(c, d.identity, d.definition)
    absent_handler = %{caller | coordinator: %{c | handlers: []}}
    assert {:ok, recovered} = Caller.advance(absent_handler, "old")
    assert recovered.intents["a"] == accepted.facts.intent.id
    assert recovered.aggregate == nil
  end

  test "caller storage unavailable never submits, and unknown storage formats fail closed", %{
    caller: caller,
    coordinator: c
  } do
    unavailable = %{caller | repo: :missing_caller}

    assert {:error, :caller_store_unavailable} =
             Caller.open(unavailable, "round", [dependency("a", "1")])

    assert {:error, :caller_store_unavailable} = Caller.advance(unavailable, "round")
    assert {:ok, []} = Coordinator.discover(c)
    assert {:ok, _round} = Caller.open(caller, "version", [dependency("a", "1")])

    SQL.query!(caller.repo, "UPDATE caller_rounds SET progress=? WHERE owner=? AND round_key=?", [
      ~s({"version":99,"value":null}),
      caller.owner,
      "version"
    ])

    assert {:error, :unsupported_storage_format} = Caller.advance(caller, "version")
    assert {:ok, []} = Coordinator.discover(c)
    assert_raise ArgumentError, fn -> Caller.start_link(database: ":memory:") end
  end

  test "restart discovers original round keys in bounded owner-scoped pages", %{
    caller: caller,
    coordinator: c,
    caller_child: child,
    caller_path: path
  } do
    for key <- ["b", "a", "c"],
        do: assert(match?({:ok, _}, Caller.open(caller, key, [dependency("a", key)])))

    other = Caller.new(caller.repo, c, "agent-2")
    assert {:ok, _round} = Caller.open(other, "foreign", [dependency("a", "other")])
    stop_supervised!(child)
    {_child, restarted} = repo(Caller, path)
    restored = Caller.new(restarted, c, "agent-1")
    assert {:ok, ["a", "b"]} = Caller.discover(restored, "", 2)
    assert {:ok, ["c"]} = Caller.discover(restored, "b", 2)
    assert {:ok, []} = Caller.discover(restored, "c", 2)
    assert {:error, :invalid_round_page} = Caller.discover(restored, "", 0)
    assert {:ok, []} = Coordinator.discover(c)
  end

  test "manifest capacity is checked before any Authority submission", %{
    caller: caller,
    coordinator: c
  } do
    large = String.duplicate("x", 500_000)

    dependencies =
      for n <- 1..35, do: dependency(Integer.to_string(n), "shared", "beamlet.echo.v1", large)

    assert {:error, :caller_capacity_exceeded} = Caller.open(caller, "large", dependencies)
    assert {:error, :round_not_found} = Caller.read(caller, "large")
    assert {:ok, []} = Coordinator.discover(c)
  end

  test "authority outage preserves partial caller progress without creating Failed", %{
    caller: caller,
    coordinator: c
  } do
    assert {:ok, _round} =
             Caller.open(caller, "offline", [dependency("a", "1"), approval("b", "2")])

    assert {:ok, submitted} = Caller.advance(caller, "offline")
    run_round(c, submitted)
    assert {:ok, partial} = Caller.advance(caller, "offline")
    offline = %{caller | coordinator: %{c | repo: :missing_authority}}
    assert {:error, %Error{stage: :read, slot: "b"}} = Caller.advance(offline, "offline")
    assert {:ok, ^partial} = Caller.read(caller, "offline")
    assert {:ok, ^partial} = Caller.advance(caller, "offline")
  end
end
