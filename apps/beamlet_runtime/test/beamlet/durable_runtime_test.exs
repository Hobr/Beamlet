defmodule Beamlet.Runtime.DurableHandler do
  @moduledoc false
  @behaviour Beamlet.Actions.Handler

  def run(payload, context) do
    if payload["trap"], do: Process.flag(:trap_exit, true)
    send(context.settings, {:handler_started, self(), context.remaining_ms})

    case payload do
      %{"mode" => "hold"} ->
        receive do
          :release -> {:ok, %{"echo" => payload["marker"]}}
          :crash -> exit(:unrelated_crash)
        end

      _ ->
        {:ok, %{"echo" => payload["marker"]}}
    end
  end
end

defmodule Beamlet.Runtime.DurableRuntimeTest do
  use ExUnit.Case, async: false
  alias Beamlet.Actions.Operation
  alias Beamlet.Runtime
  alias Beamlet.Runtime.Persistence

  alias Beamlet.Storage.{
    Codec,
    Dataset,
    ExecutorJournal,
    ExecutorJournalRepo,
    OperationRecords,
    SQLiteAuthorityRepo
  }

  alias Beamlet.Storage.Schema.JournalAttempt

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "beamlet-runtime-durable-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    authority = Path.join(dir, "authority.db")
    journal = Path.join(dir, "journal.db")

    authority_opts = [
      database: authority,
      peer_database: journal,
      dataset_id: Ecto.UUID.generate()
    ]

    journal_opts = [
      database: journal,
      peer_database: authority,
      dataset_id: Ecto.UUID.generate()
    ]

    {:ok, _pid} = Dataset.initialize(SQLiteAuthorityRepo, authority_opts)
    {:ok, _pid} = Dataset.initialize(ExecutorJournalRepo, journal_opts)

    on_exit(fn ->
      stop_repo(SQLiteAuthorityRepo)
      stop_repo(ExecutorJournalRepo)
      File.rm_rf!(dir)
    end)

    %{
      authority_id: Ecto.UUID.generate(),
      executor_id: Ecto.UUID.generate(),
      authority_opts: authority_opts,
      journal_opts: journal_opts
    }
  end

  test "authority prepare and send claim commit before admit; journal start intent precedes the worker",
       context do
    persistence = persistence(context)
    boot(persistence)

    {:ok, ref} = Runtime.submit(operation("hold"), persistence: persistence)
    assert_receive {:handler_started, _worker, _payload}, 2000

    assert {:ok, authority} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
    assert authority["attempt"]["dispatch_state"] == "send_claimed"
    attempt_id = authority["attempt"]["attempt_id"]

    # The worker is already running, so the executor's start intent must exist.
    assert {:ok, journal} =
             ExecutorJournal.fetch(ExecutorJournalRepo, context.authority_id, attempt_id)

    assert journal["state"] == "start_intent"
    assert ExecutorJournalRepo.aggregate(JournalAttempt, :count) == 1
  end

  test "a failed journal write rejects the attempt and starts no worker", context do
    persistence = persistence(context)
    boot(persistence)
    # The journal becomes unwritable after a successful boot; admission must stop.
    ExecutorJournalRepo.stop()

    {:ok, ref} = Runtime.submit(operation("hold"), persistence: persistence)
    assert_receive {:beamlet_operation, ^ref, {:result, result}}, 3000
    assert result.status == :error
    assert result.reason == :durable_unavailable
    refute_received {:handler_started, _, _}

    assert {:ok, authority} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
    assert authority["operation"]["accepted_result"]["status"] == "error"
    assert authority["attempt"]["dispatch_state"] == "send_claimed"
  end

  test "a terminal write that cannot commit leaves the result uncertain, not an error",
       context do
    persistence = persistence(context)
    boot(persistence)
    {:ok, ref} = Runtime.submit(operation("hold"), persistence: persistence)
    assert_receive {:handler_started, worker, _payload}, 2000

    # The handler has run and may have produced external effects, so losing the
    # journal at this point must not be reported as a definite failure.
    ExecutorJournalRepo.stop()
    send(worker, :release)

    assert_receive {:beamlet_operation, ^ref, {:result, result}}, 3000
    assert result.status == :uncertain
    assert result.reason == :durable_unavailable

    # Restore the journal so cleanup and later assertions can read it.
    {:ok, _pid} = Dataset.open(ExecutorJournalRepo, context.journal_opts)
  end

  test "terminal journal and accepted authority Result exist before the sink is notified",
       context do
    persistence = persistence(context)
    boot(persistence)
    parent = self()

    sink =
      spawn(fn ->
        receive do
          {:beamlet_operation, ref, {:result, result}} ->
            {:ok, authority} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
            attempt_id = authority["attempt"]["attempt_id"]
            {:ok, evidence} = Runtime.evidence(persistence, ref.id, attempt_id)

            send(
              parent,
              {:sink_observed, result, evidence.journal["state"],
               authority["operation"]["accepted_result"]}
            )
        end
      end)

    {:ok, ref} = Runtime.submit(operation("hold"), persistence: persistence, sink: sink)
    assert_receive {:handler_started, worker, _payload}, 2000
    send(worker, :release)

    assert_receive {:sink_observed, result, journal_state, accepted}, 3000
    assert result.status == :ok
    assert journal_state == "terminal"
    assert accepted["status"] == "ok"

    assert {:ok, authority} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
    attempt_id = authority["attempt"]["attempt_id"]
    {:ok, journal} = ExecutorJournal.fetch(ExecutorJournalRepo, context.authority_id, attempt_id)
    assert journal["state"] == "terminal"
    assert journal["receipt_id"] == authority["operation"]["accepted_evidence_id"]
  end

  test "a new boot marks prior start intents unknown, restores no capacity and starts no worker",
       context do
    first = persistence(context)
    supervisor = boot(first)

    {:ok, ref} = Runtime.submit(operation("hold", 60_000), persistence: first)
    assert_receive {:handler_started, _worker, _payload}, 2000
    assert {:ok, authority} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
    attempt_id = authority["attempt"]["attempt_id"]

    # Simulate VM loss: the gateway and its workers disappear without a terminal write.
    Process.exit(Process.whereis(Runtime.ExecutorGateway), :kill)
    stop_boot(supervisor)

    # The restarted gateway of the same boot owns no worker either, so the
    # orphaned intent is already classified instead of staying start_intent
    # forever (it could otherwise never become terminal or restart-unknown).
    assert {:ok, journal} =
             ExecutorJournal.fetch(ExecutorJournalRepo, context.authority_id, attempt_id)

    assert journal["state"] == "unknown_after_restart"

    second = persistence(context)
    boot(second)

    assert {:ok, restarted} =
             ExecutorJournal.fetch(ExecutorJournalRepo, context.authority_id, attempt_id)

    assert restarted["state"] == "unknown_after_restart"
    refute_received {:handler_started, _, _}
    assert :sys.get_state(Runtime.ExecutorGateway).available == %{"cpu" => 1}

    receipt = %{"version" => 1, "attempt_id" => attempt_id}
    {:ok, digest} = Codec.digest(receipt, :event)

    assert {:error, :conflict} =
             ExecutorJournal.record_terminal(ExecutorJournalRepo, %{
               authority_id: context.authority_id,
               attempt_id: attempt_id,
               expected_version: 0,
               termination: %{"kind" => "exit", "reason" => "other"},
               terminal_result: %{"status" => "ok"},
               terminal_artifacts: %{"version" => 1, "items" => %{}},
               receipt_id: Ecto.UUID.generate(),
               receipt_digest: digest,
               receipt: receipt
             })
  end

  test "duplicate receipts replay, conflicting receipts never overwrite, late evidence stays reviewable",
       context do
    persistence = persistence(context)
    boot(persistence)

    {:ok, ref} = Runtime.submit(operation("hold"), persistence: persistence)
    assert_receive {:handler_started, worker, _payload}, 2000
    send(worker, :release)
    assert_receive {:beamlet_operation, ^ref, {:result, %{status: :ok}}}, 3000

    assert {:ok, authority} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
    operation = authority["operation"]
    attempt_id = authority["attempt"]["attempt_id"]
    accepted = operation["accepted_result"]
    evidence_id = operation["accepted_evidence_id"]

    retry = fn result ->
      OperationRecords.accept_result(SQLiteAuthorityRepo, %{
        operation_id: ref.id,
        expected_version: operation["lock_version"],
        result: result,
        evidence_id: evidence_id,
        event: %{
          id: Ecto.UUID.generate(),
          type: "operation.result_accepted",
          payload: %{"retry" => true}
        }
      })
    end

    assert {:ok, replay} = retry.(accepted)
    assert replay["accepted_result"] == accepted

    conflicting = Map.put(accepted, "status", "error")
    assert {:error, :conflict} = retry.(conflicting)

    late_id = Ecto.UUID.generate()

    assert {:ok, _late} =
             OperationRecords.record_evidence(SQLiteAuthorityRepo, %{
               id: late_id,
               operation_id: ref.id,
               attempt_id: attempt_id,
               executor_id: context.executor_id,
               evidence_id: late_id,
               content: %{"version" => 1, "late" => true}
             })

    assert {:ok, after_late} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
    assert after_late["operation"]["accepted_result"] == accepted
    assert after_late["operation"]["accepted_evidence_id"] == evidence_id
    assert {:ok, evidence} = Runtime.evidence(persistence, ref.id, attempt_id)
    assert evidence.journal["state"] == "terminal"
  end

  test "durable mode keeps the first stop cause and a normal return stays ok", context do
    persistence = persistence(context)
    boot(persistence, cancel_ms: 400)

    {:ok, ref} =
      Runtime.submit(operation("hold", 5000, %{"trap" => true}), persistence: persistence)

    assert_receive {:handler_started, worker, _payload}, 2000
    assert {:ok, authority} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
    attempt_id = authority["attempt"]["attempt_id"]
    key = {ref.pid, attempt_id}
    gateway = Process.whereis(Runtime.ExecutorGateway)

    :sys.suspend(gateway)

    try do
      send(gateway, {:execution_deadline, key, worker})
      assert :ok = Runtime.cancel(ref)
    after
      :sys.resume(gateway)
    end

    assert wait_stop_source(gateway, key) == :deadline
    send(worker, :release)
    assert_receive {:beamlet_operation, ^ref, {:result, result}}, 3000
    assert result.status == :ok
    assert result.reason == nil

    assert {:ok, journal} =
             ExecutorJournal.fetch(ExecutorJournalRepo, context.authority_id, attempt_id)

    assert journal["stop_reason"] == "deadline"
    assert journal["state"] == "terminal"
  end

  test "an unrelated crash after a cancel request stays worker_lost", context do
    persistence = persistence(context)
    boot(persistence)

    {:ok, ref} =
      Runtime.submit(operation("hold", 5000, %{"trap" => true}), persistence: persistence)

    assert_receive {:handler_started, worker, _payload}, 2000
    assert :ok = Runtime.cancel(ref)
    send(worker, :crash)
    assert_receive {:beamlet_operation, ^ref, {:result, result}}, 3000
    assert result.status == :error
    assert result.reason == :worker_lost

    assert {:ok, authority} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
    attempt_id = authority["attempt"]["attempt_id"]

    assert {:ok, journal} =
             ExecutorJournal.fetch(ExecutorJournalRepo, context.authority_id, attempt_id)

    assert journal["stop_reason"] == "cancelled"
    assert journal["state"] == "terminal"
  end

  test "an expired deadline records deadline worker_stopped", context do
    persistence = persistence(context)
    boot(persistence, refresh_ms: 10_000, expiry_ms: 3000)

    {:ok, op} = Operation.new(kind: "durable")
    {:ok, _, report} = Runtime.Directory.select(op)
    wait_until(report.lease + 700)

    {:ok, ref} = Runtime.submit(operation("hold", 1400), persistence: persistence)
    assert_receive {:handler_started, _worker, remaining}, 2000
    assert remaining > 0 and remaining < 800, "remaining=#{inspect(remaining)}"
    assert_receive {:beamlet_operation, ^ref, {:result, result}}, 3000
    assert result.status == :deadline
    assert result.reason == :worker_stopped

    assert {:ok, authority} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
    attempt_id = authority["attempt"]["attempt_id"]

    assert {:ok, journal} =
             ExecutorJournal.fetch(ExecutorJournalRepo, context.authority_id, attempt_id)

    assert journal["stop_reason"] == "deadline"
    assert journal["state"] == "terminal"
  end

  defp persistence(context, overrides \\ []) do
    Persistence.new(
      Keyword.merge(
        [
          authority_repo: SQLiteAuthorityRepo,
          journal_repo: ExecutorJournalRepo,
          authority_id: context.authority_id,
          executor_id: context.executor_id,
          executor_boot_id: Ecto.UUID.generate()
        ],
        overrides
      )
    )
  end

  defp operation(mode, budget \\ 5000, payload \\ %{}) do
    {:ok, operation} =
      Operation.new(
        kind: "durable",
        payload: Map.merge(%{"mode" => mode, "marker" => "marker"}, payload),
        claims: %{"cpu" => 1},
        budget_ms: budget
      )

    operation
  end

  defp boot(persistence, overrides \\ []) do
    limits =
      Keyword.merge(
        [refresh_ms: 10, expiry_ms: 300, retention_ms: 1000, cancel_ms: 50, admission_ms: 500],
        overrides
      )

    {:ok, pid} =
      Runtime.SharedSupervisor.start_link(
        execution: true,
        handlers: %{"durable" => {Beamlet.Runtime.DurableHandler, self()}},
        pools: %{"cpu" => 1},
        persistence: persistence,
        limits: limits
      )

    Process.unlink(pid)

    on_exit(fn ->
      if Process.alive?(pid), do: Supervisor.stop(pid)
    end)

    Runtime.TestPeer.barrier("durable")
    pid
  end

  defp stop_boot(supervisor) do
    Supervisor.stop(supervisor)
    wait_unregistered(Runtime.SharedSupervisor)
  end

  defp wait_unregistered(name, attempts \\ 200)
  defp wait_unregistered(_name, 0), do: :ok

  defp wait_unregistered(name, attempts) do
    if Process.whereis(name) do
      Process.sleep(5)
      wait_unregistered(name, attempts - 1)
    else
      :ok
    end
  end

  defp wait_stop_source(gateway, key, attempts \\ 200)
  defp wait_stop_source(_gateway, _key, 0), do: :timeout

  defp wait_stop_source(gateway, key, attempts) do
    case :sys.get_state(gateway).attempts[key] do
      %{stop_source: nil} ->
        Process.sleep(5)
        wait_stop_source(gateway, key, attempts - 1)

      %{stop_source: source} ->
        source
    end
  end

  defp wait_until(time) do
    remaining = time - System.monotonic_time(:millisecond)
    if remaining > 0, do: Process.sleep(remaining)
  end

  defp stop_repo(repo) do
    if Process.whereis(repo), do: repo.stop()
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
