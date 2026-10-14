defmodule Beamlet.Agent.ContinuationTest do
  use ExUnit.Case, async: false
  alias Beamlet.Agent.Caller
  alias Beamlet.Agent.Caller.{Dependency, Repo, Round, Schema}
  alias Beamlet.{Definition, Identity}
  alias BeamletRuntime.Approval.Store, as: ApprovalStore
  alias BeamletRuntime.{Coordinator, Scheduler, Worker}
  alias BeamletRuntime.Handlers.{Approval, Echo}
  alias BeamletRuntime.Storage.{Codec, SQLite}
  alias Ecto.Adapters.SQL
  alias Ecto.Migrator

  setup do
    directory =
      Path.join(System.tmp_dir!(), "beamlet-continuation-#{System.unique_integer([:positive])}")

    {_authority_child, authority} = repo(SQLite, Path.join(directory, "authority.db"))
    caller_path = Path.join(directory, "caller.db")
    {caller_child, caller_repo} = repo(Caller, caller_path)
    {_resource_child, resource} = repo(ApprovalStore, Path.join(directory, "approvals.db"))
    :ok = SQLite.migrate(authority)
    :ok = Caller.migrate(caller_repo)
    assert {:ok, :ok} = ApprovalStore.migrate(resource, "approvals")
    service = ApprovalStore.new(resource, "approvals")

    c =
      Coordinator.new(
        repo: authority,
        collection: "collection",
        actor: "local",
        handlers: [{Echo, nil}, {Approval, %{service: service}}]
      )

    caller = Caller.new(caller_repo, c, "agent-1")
    on_exit(fn -> File.rm_rf!(directory) end)

    %{
      caller: caller,
      c: c,
      service: service,
      caller_child: caller_child,
      caller_path: caller_path
    }
  end

  defp repo(module, path) do
    child = make_ref()

    {child,
     start_supervised!(Supervisor.child_spec({module, database: path, pool_size: 1}, id: child))}
  end

  defp dependency(slot, key, input, operation \\ "beamlet.echo.v1") do
    {:ok, identity} = Identity.new("collection", "agent-1", key)
    {:ok, definition} = Definition.new(%{operation: operation, input: input})
    {:ok, dependency} = Dependency.new(slot, identity, definition)
    dependency
  end

  defp worker(c),
    do:
      start_supervised!(
        Supervisor.child_spec(
          {Worker,
           coordinator: c,
           id: Ecto.UUID.generate(),
           environment: %{"echo" => true, "approval_service" => "approvals"}},
          id: make_ref()
        )
      )

  defp partial(caller, c) do
    pending =
      dependency(
        "b",
        "b",
        %{"service" => "approvals", "subject" => "b", "responders" => ["reviewer"]},
        "human.approval.v1"
      )

    assert {:ok, _round} =
             Caller.open(caller, "original", [dependency("a", "a", %{"answer" => 42}), pending])

    assert {:ok, submitted} = Caller.advance(caller, "original")
    assert {:ok, _page} = Scheduler.scan_once(c, [worker(c)])

    eventually(fn ->
      {:ok, round} = Caller.advance(caller, "original")
      Map.has_key?(round.outcomes, "a")
    end)

    assert {:ok, round} = Caller.read(caller, "original")
    assert round.aggregate == nil
    assert round.intents == submitted.intents
    round
  end

  defp opts(slot \\ "a"),
    do: [source_round: "original", source_slot: slot, rule: "consume-success.v1"]

  defp planner(outcome),
    do:
      {:ok,
       %{
         value: %{"choice" => "echo"},
         next_round: "next",
         dependency: dependency("c", "c", outcome.value)
       }}

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

  test "decision precedes successor registration and partial A/B can drive C", %{
    caller: caller,
    c: c
  } do
    original = partial(caller, c)
    assert {:ok, decision} = Caller.decide(caller, "computation", "step", opts(), &planner/1)
    assert decision.outcome == original.outcomes["a"]
    assert decision.intent_id == original.intents["a"]
    assert decision.rule == "consume-success.v1"
    assert decision.dependency.definition.input == original.outcomes["a"].value
    assert {:error, :round_not_found} = Caller.read(caller, "next")
    assert {:ok, _round} = Caller.register_next(caller, "computation", "step")
    assert {:ok, next} = Caller.advance_next(caller, "computation", "step")
    assert Map.has_key?(next.intents, "c")
    assert {:ok, original_after} = Caller.read(caller, "original")
    assert original_after == original
    {:ok, sibling} = Coordinator.read(c, original.intents["b"])
    assert sibling.intent.phase == :open
    assert sibling.intent.outcome == nil
    assert {:ok, _page} = Scheduler.scan_once(c, [worker(c)])

    eventually(fn ->
      {:ok, result} = Caller.advance_next(caller, "computation", "step")
      result.aggregate != nil
    end)

    {:ok, result} = Caller.read(caller, "next")
    assert result.aggregate["c"]["outcome"].value == %{"answer" => 42}
  end

  test "decision survives restart before registration and never reruns planner", %{
    caller: caller,
    c: c,
    caller_child: child,
    caller_path: path
  } do
    partial(caller, c)
    assert {:ok, decision} = Caller.decide(caller, "computation", "step", opts(), &planner/1)
    stop_supervised!(child)
    {_child, restarted} = repo(Caller, path)
    restored = Caller.new(restarted, c, caller.owner)
    assert {:ok, ["step"]} = Caller.discover_decisions(restored, "computation")
    assert {:ok, ^decision} = Caller.read_decision(restored, "computation", "step")

    assert {:ok, ^decision} =
             Caller.decide(restored, "computation", "step", [], fn _ ->
               flunk("recomputed saved decision")
             end)

    assert {:error, :round_not_found} = Caller.read(restored, "next")
    assert {:ok, registered} = Caller.register_next(restored, "computation", "step")
    assert registered.dependencies == [decision.dependency]
    assert registered.intents == %{}
    assert {:ok, ^registered} = Caller.register_next(restored, "computation", "step")
  end

  test "later B completion never replaces consumed A or changes its successor", %{
    caller: caller,
    c: c,
    service: service
  } do
    original = partial(caller, c)
    assert {:ok, decision} = Caller.decide(caller, "computation", "step", opts(), &planner/1)

    assert {:ok, _receipt} =
             ApprovalStore.decide(
               service,
               c.collection,
               original.intents["b"],
               "reviewer",
               "denied"
             )

    assert {:ok, _page} = Scheduler.scan_once(c, [worker(c)])
    assert {:ok, completed} = Caller.advance(caller, "original")
    assert completed.aggregate != nil

    assert {:ok, ^decision} =
             Caller.decide(caller, "computation", "step", opts("b"), fn _ ->
               flunk("overwrote original decision")
             end)

    assert decision.source_slot == "a"
    assert decision.outcome == original.outcomes["a"]
    assert decision.dependency.identity.key == "c"
  end

  test "Pending, unknown slot and Cancelled cannot drive a Success continuation", %{
    caller: caller,
    c: c
  } do
    original = partial(caller, c)
    refuse = fn _ -> flunk("unqualified source invoked planner") end

    assert {:error, :source_not_collected} =
             Caller.decide(caller, "computation", "pending", opts("b"), refuse)

    assert {:error, :unknown_slot} =
             Caller.decide(caller, "computation", "missing", opts("absent"), refuse)

    assert {:ok, _commit} = Coordinator.cancel(c, original.intents["b"], "cancel")
    assert {:ok, _round} = Caller.advance(caller, "original")

    assert {:error, :source_not_succeeded} =
             Caller.decide(caller, "computation", "cancelled", opts("b"), refuse)

    assert {:ok, []} = Caller.discover_decisions(caller, "computation")
    assert {:error, :round_not_found} = Caller.read(caller, "next")
  end

  test "no decision means no successor registration or dispatch", %{caller: caller, c: c} do
    partial(caller, c)
    assert {:error, :decision_not_found} = Caller.register_next(caller, "computation", "absent")
    assert {:error, :decision_not_found} = Caller.advance_next(caller, "computation", "absent")
    assert {:error, :round_not_found} = Caller.read(caller, "next")
    assert {:ok, candidates} = Coordinator.discover(c)
    assert length(candidates) == 1
  end

  test "wrong input, original identity, unkeyed request and runtime choice are rejected", %{
    caller: caller,
    c: c
  } do
    original = partial(caller, c)
    {:ok, valid} = planner(original.outcomes["a"])

    invalid = [
      %{valid | dependency: dependency("c", "c", "wrong")},
      %{
        valid
        | dependency: %{valid.dependency | identity: %{valid.dependency.identity | key: nil}}
      },
      %{
        valid
        | dependency: %{valid.dependency | identity: %{valid.dependency.identity | key: "a"}}
      },
      %{
        valid
        | dependency: %{
            valid.dependency
            | identity: %{valid.dependency.identity | collection: "foreign"}
          }
      },
      %{valid | next_round: "original"},
      %{valid | value: self()},
      Map.put(valid, :extra, true)
    ]

    for {proposal, n} <- Enum.with_index(invalid) do
      assert {:error, :invalid_continuation} =
               Caller.decide(caller, "computation", Integer.to_string(n), opts(), fn _ ->
                 {:ok, proposal}
               end)
    end

    assert {:ok, []} = Caller.discover_decisions(caller, "computation")
  end

  test "planner failure leaves no decision or successor", %{caller: caller, c: c} do
    partial(caller, c)

    assert {:error, :planner_failed} =
             Caller.decide(caller, "computation", "raise", opts(), fn _ -> raise "failed" end)

    assert {:error, :planner_failed} =
             Caller.decide(caller, "computation", "exit", opts(), fn _ -> exit(:failed) end)

    assert {:error, :invalid_planner_reply} =
             Caller.decide(caller, "computation", "bad", opts(), fn _ -> :ok end)

    assert {:error, :no_choice} =
             Caller.decide(caller, "computation", "refuse", opts(), fn _ ->
               {:error, :no_choice}
             end)

    assert {:ok, []} = Caller.discover_decisions(caller, "computation")
  end

  test "decision reserves its exact successor manifest across steps", %{caller: caller, c: c} do
    original = partial(caller, c)
    assert {:ok, decision} = Caller.decide(caller, "computation", "step", opts(), &planner/1)
    wrong = dependency("c", "changed", original.outcomes["a"].value)
    assert {:error, :round_definition_conflict} = Caller.open(caller, "next", [wrong])

    assert {:error, :successor_round_reserved} =
             Caller.decide(caller, "other", "step", opts(), &planner/1)

    assert {:ok, manifest} = Caller.open(caller, "next", [decision.dependency])
    assert {:ok, ^manifest} = Caller.register_next(caller, "computation", "step")
  end

  test "existing successor round cannot be retrospectively attached to a decision", %{
    caller: caller,
    c: c
  } do
    original = partial(caller, c)
    {:ok, proposal} = planner(original.outcomes["a"])
    assert {:ok, _round} = Caller.open(caller, "next", [proposal.dependency])

    assert {:error, :successor_round_exists} =
             Caller.decide(caller, "computation", "step", opts(), &planner/1)

    assert {:error, :decision_not_found} = Caller.read_decision(caller, "computation", "step")
  end

  test "independent Repos race and both recover the first committed choice", %{
    caller: caller,
    c: c,
    caller_path: path
  } do
    partial(caller, c)
    {_child, peer_repo} = repo(Caller, path)
    :ok = Caller.migrate(peer_repo)
    peer = Caller.new(peer_repo, c, caller.owner)
    parent = self()

    tasks =
      for {instance, choice} <- [{caller, "first"}, {peer, "second"}] do
        Task.async(fn ->
          Caller.decide(instance, "computation", "step", opts(), fn outcome ->
            send(parent, {:planning, self()})

            receive do
              :commit -> :ok
            after
              5000 -> raise "missing signal"
            end

            {:ok, proposal} = planner(outcome)
            {:ok, %{proposal | value: choice, dependency: dependency("c", choice, outcome.value)}}
          end)
        end)
      end

    assert_receive {:planning, p1}, 1000
    assert_receive {:planning, p2}, 1000
    send(p1, :commit)
    send(p2, :commit)
    [first, second] = Enum.map(tasks, &Task.await/1)
    assert {:ok, decision} = first
    assert second == first
    assert decision.value in ["first", "second"]
    assert decision.dependency.identity.key == decision.value

    tasks =
      for instance <- [caller, peer],
          do: Task.async(fn -> Caller.advance_next(instance, "computation", "step") end)

    assert Enum.all?(Enum.map(tasks, &Task.await/1), &match?({:ok, _}, &1))
    {:ok, next} = Caller.read(peer, "next")
    assert map_size(next.intents) == 1
    {:ok, facts} = Coordinator.read(c, next.intents["c"])
    assert facts.intent.identity == decision.dependency.identity
  end

  test "accepted C with lost reply recovers after restart and Closed replay adds no Execution", %{
    caller: caller,
    c: c,
    caller_child: child,
    caller_path: path
  } do
    partial(caller, c)
    assert {:ok, decision} = Caller.decide(caller, "computation", "step", opts(), &planner/1)
    assert {:ok, _round} = Caller.register_next(caller, "computation", "step")

    assert {:ok, accepted} =
             Coordinator.submit(c, decision.dependency.identity, decision.dependency.definition)

    stop_supervised!(child)
    {_child, restarted} = repo(Caller, path)
    restored = Caller.new(restarted, c, caller.owner)
    assert {:ok, next} = Caller.advance_next(restored, "computation", "step")
    assert next.intents["c"] == accepted.facts.intent.id
    assert {:ok, _page} = Scheduler.scan_once(c, [worker(c)])

    eventually(fn ->
      {:ok, result} = Caller.advance_next(restored, "computation", "step")
      result.aggregate != nil
    end)

    {:ok, closed} = Coordinator.read(c, next.intents["c"])
    assert map_size(closed.intent.executions) == 1
    assert {:ok, _round} = Caller.advance_next(restored, "computation", "step")
    assert {:ok, ^closed} = Coordinator.read(c, next.intents["c"])
  end

  test "decision write failure sends nothing and permits original-step recovery", %{
    caller: caller,
    c: c
  } do
    partial(caller, c)
    SQL.query!(caller.repo, "PRAGMA query_only=ON", [])

    try do
      assert {:error, :caller_commit_indeterminate} =
               Caller.decide(caller, "computation", "step", opts(), &planner/1)

      assert {:error, :decision_not_found} = Caller.read_decision(caller, "computation", "step")
      assert {:error, :round_not_found} = Caller.read(caller, "next")
    after
      SQL.query!(caller.repo, "PRAGMA query_only=OFF", [])
    end

    assert {:ok, _decision} = Caller.decide(caller, "computation", "step", opts(), &planner/1)
    assert {:ok, next} = Caller.advance_next(caller, "computation", "step")
    assert map_size(next.intents) == 1
  end

  test "decision scope isolates owners and collections and validates new options", %{
    caller: caller,
    c: c
  } do
    partial(caller, c)
    assert {:ok, _decision} = Caller.decide(caller, "computation", "step", opts(), &planner/1)
    peer = Caller.new(caller.repo, c, "other")
    assert {:error, :decision_not_found} = Caller.read_decision(peer, "computation", "step")
    assert {:ok, []} = Caller.discover_decisions(peer, "computation")
    foreign = %{caller | coordinator: %{c | collection: "foreign"}}

    assert {:error, :decision_collection_mismatch} =
             Caller.read_decision(foreign, "computation", "step")

    assert {:error, :invalid_decision_scope} = Caller.read_decision(caller, "", "step")

    assert {:error, :invalid_decision_page} =
             Caller.discover_decisions(caller, "computation", "", 0)

    assert {:error, :invalid_decision_options} =
             Caller.decide(caller, "computation", "new", [], &planner/1)
  end

  test "v1 caller migration preserves the original manifest and progress before adding decisions",
       %{caller: caller, c: c, caller_path: path} do
    original = partial(caller, c)
    {_child, legacy_repo} = repo(Caller, Path.join(Path.dirname(path), "legacy.db"))
    previous = Repo.put_dynamic_repo(legacy_repo)

    try do
      Migrator.run(Repo, [{1, Schema}], :up, all: true, log: false)
    after
      Repo.put_dynamic_repo(previous)
    end

    SQL.query!(
      legacy_repo,
      "INSERT INTO caller_rounds(owner,round_key,collection,manifest,progress) VALUES(?,?,?,?,?)",
      [
        original.owner,
        original.key,
        original.collection,
        Codec.encode(Enum.map(original.dependencies, &Dependency.pack/1)),
        Codec.encode(Round.progress(original))
      ]
    )

    :ok = Caller.migrate(legacy_repo)
    :ok = Caller.migrate(legacy_repo)
    upgraded = Caller.new(legacy_repo, c, caller.owner)
    assert {:ok, ^original} = Caller.read(upgraded, "original")
    assert {:ok, ["original"]} = Caller.discover(upgraded)
    assert {:ok, decision} = Caller.decide(upgraded, "computation", "step", opts(), &planner/1)
    assert decision.outcome == original.outcomes["a"]
    assert {:ok, next} = Caller.advance_next(upgraded, "computation", "step")
    assert map_size(next.intents) == 1
  end

  test "registered successor restart before send recovers its exact saved request", %{
    caller: caller,
    c: c,
    caller_child: child,
    caller_path: path
  } do
    partial(caller, c)
    assert {:ok, decision} = Caller.decide(caller, "computation", "step", opts(), &planner/1)
    assert {:ok, manifest} = Caller.register_next(caller, "computation", "step")
    stop_supervised!(child)
    {_child, restarted} = repo(Caller, path)
    restored = Caller.new(restarted, c, caller.owner)
    assert {:ok, ^manifest} = Caller.read(restored, "next")
    assert manifest.intents == %{}
    assert {:ok, next} = Caller.advance_next(restored, "computation", "step")
    {:ok, facts} = Coordinator.read(c, next.intents["c"])
    assert facts.intent.identity == decision.dependency.identity
    assert facts.intent.definition == decision.dependency.definition
  end

  test "registration write failure keeps decision and sends no successor", %{caller: caller, c: c} do
    partial(caller, c)
    assert {:ok, decision} = Caller.decide(caller, "computation", "step", opts(), &planner/1)
    SQL.query!(caller.repo, "PRAGMA query_only=ON", [])

    try do
      assert {:error, :caller_commit_indeterminate} =
               Caller.advance_next(caller, "computation", "step")

      assert {:ok, ^decision} = Caller.read_decision(caller, "computation", "step")
      assert {:error, :round_not_found} = Caller.read(caller, "next")
      assert {:ok, candidates} = Coordinator.discover(c)
      assert length(candidates) == 1
    after
      SQL.query!(caller.repo, "PRAGMA query_only=OFF", [])
    end

    assert {:ok, next} = Caller.advance_next(caller, "computation", "step")
    assert next.dependencies == [decision.dependency]
  end

  test "offline Authority reuses decision without planning; successor stays recoverable", %{
    caller: caller,
    c: c
  } do
    partial(caller, c)
    assert {:ok, decision} = Caller.decide(caller, "computation", "step", opts(), &planner/1)
    offline = %{caller | coordinator: %{c | repo: :missing_authority}}
    assert {:ok, ^decision} = Caller.decide(offline, "computation", "step", nil, nil)
    assert {:ok, manifest} = Caller.register_next(offline, "computation", "step")

    assert {:error, %Caller.Error{stage: :submit, slot: "c"}} =
             Caller.advance_next(offline, "computation", "step")

    assert {:ok, ^manifest} = Caller.read(caller, "next")
    assert {:ok, next} = Caller.advance_next(caller, "computation", "step")
    assert map_size(next.intents) == 1
  end

  test "different step identities remain independently discoverable", %{
    caller: caller,
    c: c
  } do
    partial(caller, c)
    assert {:ok, _decision} = Caller.decide(caller, "computation", "a", opts(), &planner/1)

    second = fn outcome ->
      {:ok, p} = planner(outcome)
      {:ok, %{p | next_round: "next-2", dependency: dependency("c", "c-2", outcome.value)}}
    end

    assert {:ok, _decision} = Caller.decide(caller, "computation", "b", opts(), second)
    assert {:ok, ["a"]} = Caller.discover_decisions(caller, "computation", "", 1)
    assert {:ok, ["b"]} = Caller.discover_decisions(caller, "computation", "a", 1)
    assert {:ok, []} = Caller.discover_decisions(caller, "computation", "b", 1)
    assert {:ok, []} = Caller.discover_decisions(caller, "other")
  end

  test "caller process killed while planning leaves no successor and original step can retry", %{
    caller: caller,
    c: c
  } do
    partial(caller, c)
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        Caller.decide(caller, "computation", "step", opts(), fn _outcome ->
          send(parent, :planning)

          receive do
            :finish -> {:error, :unused}
          end
        end)
      end)

    assert_receive :planning, 1000
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    assert {:error, :decision_not_found} = Caller.read_decision(caller, "computation", "step")
    assert {:error, :round_not_found} = Caller.read(caller, "next")
    assert {:ok, _decision} = Caller.decide(caller, "computation", "step", opts(), &planner/1)
    assert {:ok, next} = Caller.advance_next(caller, "computation", "step")
    assert map_size(next.intents) == 1
  end

  test "C completes while caller storage is offline and original Outcome is collected after restart",
       %{caller: caller, c: c, caller_child: child, caller_path: path} do
    partial(caller, c)
    assert {:ok, _decision} = Caller.decide(caller, "computation", "step", opts(), &planner/1)
    assert {:ok, next} = Caller.advance_next(caller, "computation", "step")
    stop_supervised!(child)
    assert {:ok, _page} = Scheduler.scan_once(c, [worker(c)])

    eventually(fn ->
      {:ok, facts} = Coordinator.read(c, next.intents["c"])
      facts.intent.outcome != nil
    end)

    {:ok, closed} = Coordinator.read(c, next.intents["c"])
    {_child, restarted} = repo(Caller, path)
    restored = Caller.new(restarted, c, caller.owner)
    assert {:ok, ^next} = Caller.read(restored, "next")
    assert {:ok, completed} = Caller.advance_next(restored, "computation", "step")
    assert completed.aggregate["c"]["outcome"] == closed.intent.outcome
    assert {:ok, ^closed} = Coordinator.read(c, next.intents["c"])
  end
end
