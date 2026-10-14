defmodule BeamletRuntime.ReconciliationTest do
  use ExUnit.Case, async: false
  alias Beamlet.{Definition, Identity, Judgment, Reconciliation, Report}
  alias Beamlet.Reconciliation.{Command, Policy}
  alias BeamletRuntime.Coordinator
  alias BeamletRuntime.Storage.{Codec, Error, SQLite}
  alias Ecto.Adapters.SQL

  setup do
    directory =
      Path.join(System.tmp_dir!(), "beamlet-reconcile-#{System.unique_integer([:positive])}")

    path = Path.join(directory, "authority.db")
    {child, repo} = repo(path)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{repo: repo, child: child, path: path}
  end

  defp repo(path) do
    child = make_ref()

    repo =
      start_supervised!(
        Supervisor.child_spec({SQLite, database: path, pool_size: 1, busy_timeout: 1000},
          id: child
        )
      )

    :ok = SQLite.migrate(repo)
    {child, repo}
  end

  defp coordinator(
         repo,
         policy \\ %Policy{operators: ["operator"]},
         access \\ %{may_submit: true, may_read: true}
       ) do
    Coordinator.new(
      repo: repo,
      collection: "collection",
      actor: "operator",
      handlers: [],
      reconciliation: fn _intent, _command, _context -> {:ok, policy, access} end
    )
  end

  defp step(repo, id, command) do
    assert {:ok, committed} = SQLite.command(repo, "collection", id, command, "operator")
    committed
  end

  defp facts(repo, id) do
    assert {:ok, facts} = SQLite.read(repo, "collection", id)
    facts
  end

  defp fixture(repo, key \\ "key") do
    {:ok, identity} = Identity.new("collection", "agent", key)
    {:ok, definition} = Definition.new(%{operation: "op.v1", input: nil, policy: :retry_once})
    {:ok, submitted} = SQLite.submit(repo, identity, definition, "operator")
    id = submitted.facts.intent.id
    step(repo, id, {:create_execution, "old"})
    {:claimed, token} = step(repo, id, {:claim, "old", "worker", "session", 0, 60_000}).reply

    binding = %{
      "operation" => "op.v1",
      "handler" => "handler",
      "protocol" => "protocol",
      "resource" => %{"account" => "a"},
      "idempotency" => %{
        "protocol" => "dedupe",
        "key" => id,
        "scope" => %{"account" => "a"},
        "valid_through" => nil
      }
    }

    # Explicit expiry fixture avoids a wall-clock wait; it changes only lease controls.
    step(repo, id, {:authorize, token, binding})
    current = facts(repo, id).intent

    expired = %{
      current
      | executions:
          Map.update!(current.executions, "old", fn e ->
            %{e | lease: %{e.lease | expires_at: 0}}
          end)
    }

    SQL.query!(repo, "UPDATE beamlet_intents SET snapshot=? WHERE collection=? AND id=?", [
      Codec.encode(expired),
      "collection",
      id
    ])

    step(repo, id, {:expire, "old"})
    step(repo, id, {:replace_execution, "old", "new", "recover"})

    success = %Report{
      id: "success",
      token: token,
      operation: "op.v1",
      kind: :success,
      body: %{"result" => "done"}
    }

    step(repo, id, {:record_report, success})
    {id, success}
  end

  defp proposal(repo, id, report, kind \\ :adopt_success, opts \\ %{}, key \\ "command") do
    {:ok, d} =
      Reconciliation.propose(
        facts(repo, id).intent,
        Map.merge(%{kind: kind, report: report, actor: {:operator, "operator"}}, opts)
      )

    {:ok, c} = Command.new(key, d)
    c
  end

  test "adoption, command, Outcome and History commit together and survive a complete Repo restart",
       %{repo: repo, child: child, path: path} do
    {id, success} = fixture(repo)
    c = coordinator(repo)
    cmd = proposal(repo, id, success)
    assert {:ok, committed} = Coordinator.reconcile(c, id, cmd)
    assert {:committed, record} = committed.reply
    assert record.result == committed.facts.intent.outcome
    assert Enum.map(committed.events, & &1.kind) == [:evidence_reconciled, :outcome_accepted]
    stop_supervised!(child)
    {_child, restored} = repo(path)
    read_only = coordinator(restored, %Policy{}, %{may_submit: false, may_read: true})
    assert {:ok, replay} = Coordinator.reconcile(read_only, id, cmd)
    assert replay.reply == committed.reply
    assert replay.facts == committed.facts
    assert replay.events == []
    {:ok, history} = SQLite.history(restored, "collection", id, replay.facts.revision)
    kinds = Enum.map(history.entries, & &1.event.kind)
    assert Enum.count(kinds, &(&1 == :evidence_reconciled)) == 1
    assert Enum.count(kinds, &(&1 == :outcome_accepted)) == 1

    assert SQL.query!(restored, "SELECT count(*) FROM beamlet_outcomes WHERE intent_id=?", [id]).rows ==
             [[1]]
  end

  test "History failure rolls back decision, original command, Outcome and snapshot", %{
    repo: repo
  } do
    {id, success} = fixture(repo)
    cmd = proposal(repo, id, success)
    before = facts(repo, id)

    SQL.query!(
      repo,
      "CREATE TRIGGER fail_reconcile BEFORE INSERT ON beamlet_history BEGIN SELECT RAISE(ABORT, 'injected history failure'); END",
      []
    )

    assert {:error, %Error{kind: :indeterminate}} =
             Coordinator.reconcile(coordinator(repo), id, cmd)

    assert facts(repo, id) == before

    assert SQL.query!(repo, "SELECT count(*) FROM beamlet_outcomes WHERE intent_id=?", [id]).rows ==
             [[0]]

    SQL.query!(repo, "DROP TRIGGER fail_reconcile", [])
    assert {:ok, %{reply: {:committed, _}}} = Coordinator.reconcile(coordinator(repo), id, cmd)
  end

  test "durable stale rejection replays its old review even after closure and restart", %{
    repo: repo,
    child: child,
    path: path
  } do
    {id, success} = fixture(repo)
    cmd = proposal(repo, id, success)
    step(repo, id, {:record_report, %{success | id: "late"}})
    before = facts(repo, id)
    assert {:ok, rejected} = Coordinator.reconcile(coordinator(repo), id, cmd)
    assert {:stale, original} = rejected.reply
    assert rejected.facts.revision == before.revision + 1
    assert rejected.facts.intent.judgment_revision == before.intent.judgment_revision
    assert original.result.view == Judgment.view(before.intent)
    Coordinator.cancel(coordinator(repo), id, "stop")
    stop_supervised!(child)
    {_child, restored} = repo(path)
    assert {:ok, replay} = Coordinator.reconcile(coordinator(restored), id, cmd)
    assert replay.reply == rejected.reply
    assert replay.events == []
    assert replay.facts.intent.outcome.kind == :cancelled
  end

  test "independent Repos racing one command commit exactly one decision and original result", %{
    repo: repo,
    path: path
  } do
    {id, success} = fixture(repo)
    cmd = proposal(repo, id, success)
    {_child, peer} = repo(path)

    tasks =
      for r <- [repo, peer, repo, peer],
          do: Task.async(fn -> Coordinator.reconcile(coordinator(r), id, cmd) end)

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert length(Enum.uniq(Enum.map(results, fn {:ok, c} -> c.reply end))) == 1
    assert length(facts(repo, id).intent.decisions) == 1
    assert map_size(facts(repo, id).intent.commands) == 1
  end

  test "allowed unreadable command commits without leaking facts, and can later be read without submit permission",
       %{repo: repo} do
    {id, success} = fixture(repo)
    cmd = proposal(repo, id, success)

    hidden =
      coordinator(repo, %Policy{operators: ["operator"]}, %{may_submit: true, may_read: false})

    assert {:error, :command_forbidden} = Coordinator.reconcile(hidden, id, cmd)
    assert facts(repo, id).intent.outcome.kind == :succeeded
    readable = coordinator(repo, %Policy{}, %{may_submit: false, may_read: true})
    assert {:ok, %{reply: {:committed, _}}} = Coordinator.reconcile(readable, id, cmd)

    assert {:error, :command_forbidden} =
             Coordinator.reconcile(
               %{
                 hidden
                 | reconciliation: fn _, _, _ ->
                     {:ok, %Policy{}, %{may_submit: false, may_read: false}}
                   end
               },
               id,
               cmd
             )
  end

  test "forbidden admission does not store a rejection or consume the key", %{repo: repo} do
    {id, success} = fixture(repo)
    cmd = proposal(repo, id, success)
    before = facts(repo, id)

    assert {:error, :command_forbidden} =
             Coordinator.reconcile(coordinator(repo, %Policy{}), id, cmd)

    assert facts(repo, id) == before
    assert {:ok, %{reply: {:committed, _}}} = Coordinator.reconcile(coordinator(repo), id, cmd)
  end

  test "same identity with changed content conflicts and scopes do not share command records", %{
    repo: repo
  } do
    {id, success} = fixture(repo)
    cmd = proposal(repo, id, success)
    assert {:ok, _} = Coordinator.reconcile(coordinator(repo), id, cmd)

    changed = %{
      cmd
      | decision: %{cmd.decision | kind: :exclude_from_judgment, basis: :contract_exclusion}
    }

    assert {:ok, %{reply: {:command_identity_conflict, ^changed}, events: []}} =
             Coordinator.reconcile(coordinator(repo), id, changed)

    {second, other} = fixture(repo, "other")

    assert {:ok, %{reply: {:ineligible, _}}} =
             Coordinator.reconcile(coordinator(repo), second, cmd)

    own = proposal(repo, second, other, :adopt_success, %{}, "own")

    assert {:ok, %{reply: {:committed, _}}} =
             Coordinator.reconcile(coordinator(repo), second, own)

    assert facts(repo, id).intent.outcome.execution_id == "old"
  end

  test "actual readonly SQL failure leaves the command recoverable by original identity", %{
    repo: repo
  } do
    {id, success} = fixture(repo)
    cmd = proposal(repo, id, success)
    before = facts(repo, id)
    SQL.query!(repo, "PRAGMA query_only=ON", [])

    try do
      assert {:error, %Error{}} = Coordinator.reconcile(coordinator(repo), id, cmd)
    after
      SQL.query!(repo, "PRAGMA query_only=OFF", [])
    end

    assert facts(repo, id) == before
    assert {:ok, %{reply: {:committed, _}}} = Coordinator.reconcile(coordinator(repo), id, cmd)
  end

  test "v1 snapshot imports a fresh judgment baseline; subsequent commit uses the current codec and incomplete v2 fails closed",
       %{repo: repo} do
    {id, success} = fixture(repo)
    current = facts(repo, id).intent
    encoded = Jason.decode!(Codec.encode(current))
    fields = encoded["value"]["fields"]["$map"]

    legacy_fields =
      Enum.reject(fields, fn [%{"$atom" => name}, _] ->
        name in ["judgment_revision", "decisions", "commands"]
      end)

    old =
      put_in(encoded, ["value", "fields", "$map"], legacy_fields)
      |> Map.put("version", 1)
      |> Jason.encode!()

    SQL.query!(repo, "UPDATE beamlet_intents SET snapshot=? WHERE id=?", [old, id])
    assert facts(repo, id).intent.judgment_revision == 0
    assert facts(repo, id).intent.decisions == []
    assert facts(repo, id).intent.executions == current.executions

    assert {:error, :corrupt_storage_value} =
             Codec.decode(Jason.encode!(Map.put(Jason.decode!(old), "version", 2)))

    cmd = proposal(repo, id, success)
    assert {:ok, %{reply: {:committed, _}}} = Coordinator.reconcile(coordinator(repo), id, cmd)
    [[stored]] = SQL.query!(repo, "SELECT snapshot FROM beamlet_intents WHERE id=?", [id]).rows
    assert Jason.decode!(stored)["version"] == 3
  end

  test "conflict dispositions and partial withdrawal survive resource-independent Authority restart",
       %{repo: repo, child: child, path: path} do
    {id, success} = fixture(repo)
    failure = %{success | id: "failure", kind: :failure, body: "failure"}
    step(repo, id, {:record_report, failure})

    items =
      for r <- [success, failure],
          do: %{report: r, treatment: :exclude, basis: :contract_exclusion}

    p = %Policy{operators: ["operator"], resolutions: [items]}
    cmd = proposal(repo, id, success, :exclude_all_evidence, %{evidence: items})
    assert {:ok, applied} = Coordinator.reconcile(coordinator(repo, p), id, cmd)
    assert Judgment.no_conflicts?(applied.facts.intent)
    assert Judgment.knowledge(applied.facts.intent, "old") == nil
    assert applied.facts.intent.executions["old"].conflict
    stop_supervised!(child)
    {_child, restored} = repo(path)
    assert facts(restored, id) == applied.facts
    assert {:ok, replay} = Coordinator.reconcile(coordinator(restored), id, cmd)
    assert replay.reply == applied.reply
    refs = [%{decision_index: 0, reports: [success]}]

    withdraw =
      proposal(restored, id, success, :withdraw_disposition, %{supersedes: refs}, "withdraw")

    authorized = coordinator(restored, %Policy{operators: ["operator"], withdrawals: [refs]})
    assert {:ok, removed} = Coordinator.reconcile(authorized, id, withdraw)
    assert {:committed, %{result: nil}} = removed.reply
    assert removed.facts.intent.outcome == nil
    refute Judgment.no_conflicts?(removed.facts.intent)
    assert length(Judgment.bindings(removed.facts.intent)) == 1
    assert facts(restored, id) == removed.facts
    assert {:ok, duplicate} = Coordinator.reconcile(coordinator(restored), id, withdraw)
    assert duplicate.reply == removed.reply
  end

  test "semantic rule retirement blocks new commands but preserves accepted decision and original replay",
       %{repo: repo} do
    {id, success} = fixture(repo)

    rule = %{
      id: "rule",
      version: "v1",
      kinds: [:exclude_from_judgment],
      query_required: false,
      evidence_required: false
    }

    opts = %{actor: {:rule, "rule", "v1"}}
    cmd = proposal(repo, id, success, :exclude_from_judgment, opts)
    p = %Policy{registered_rules: [rule], excludable: [success]}
    assert {:ok, accepted} = Coordinator.reconcile(coordinator(repo, p), id, cmd)
    assert Judgment.excluded?(facts(repo, id).intent, success)
    retired = coordinator(repo, %Policy{}, %{may_submit: true, may_read: true})
    assert {:ok, replay} = Coordinator.reconcile(retired, id, cmd)
    assert replay.reply == accepted.reply
    assert replay.facts == accepted.facts
    fresh = proposal(repo, id, success, :exclude_from_judgment, opts, "new")
    assert {:error, :command_forbidden} = Coordinator.reconcile(retired, id, fresh)
    assert facts(repo, id) == accepted.facts
    assert accepted.facts.intent.decisions |> hd() |> Map.fetch!(:policy) == p
  end

  test "domain rejection History failure rolls back the rejected identity before a retry", %{
    repo: repo
  } do
    {id, success} = fixture(repo)
    cmd = proposal(repo, id, success, :exclude_from_judgment)
    before = facts(repo, id)

    SQL.query!(
      repo,
      "CREATE TRIGGER fail_rejection BEFORE INSERT ON beamlet_history BEGIN SELECT RAISE(ABORT, 'injected rejection failure'); END",
      []
    )

    assert {:error, %Error{kind: :indeterminate}} =
             Coordinator.reconcile(coordinator(repo), id, cmd)

    assert facts(repo, id) == before
    SQL.query!(repo, "DROP TRIGGER fail_rejection", [])
    assert {:ok, rejected} = Coordinator.reconcile(coordinator(repo), id, cmd)
    assert {:ineligible, _} = rejected.reply
    improved = coordinator(repo, %Policy{operators: ["operator"], excludable: [success]})
    assert {:ok, replay} = Coordinator.reconcile(improved, id, cmd)
    assert replay.reply == rejected.reply
    assert replay.facts == rejected.facts
  end

  test "trusted verifier is disabled by default and malformed verifier output never changes facts",
       %{repo: repo} do
    {id, success} = fixture(repo)
    cmd = proposal(repo, id, success)
    before = facts(repo, id)
    c = coordinator(repo)

    assert {:error, :reconciliation_disabled} =
             Coordinator.reconcile(%{c | reconciliation: nil}, id, cmd)

    assert {:error, :invalid_reconciliation_verifier_reply} =
             Coordinator.reconcile(%{c | reconciliation: fn _, _, _ -> :ok end}, id, cmd)

    assert {:error, :invalid_command_access} =
             Coordinator.reconcile(
               coordinator(repo, %Policy{}, %{may_submit: "yes", may_read: true}),
               id,
               cmd
             )

    assert facts(repo, id) == before
  end
end
