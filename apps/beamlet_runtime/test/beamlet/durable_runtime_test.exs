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
  alias Beamlet.Actions.Storage.Profiles
  alias Beamlet.Runtime
  alias Beamlet.Runtime.Persistence

  alias Beamlet.Storage.Dataset

  alias Beamlet.Actions.Storage.{
    Codec,
    DispatchScopes,
    ExecutorJournal,
    ExecutorJournalRepo,
    OperationRecords,
    SQLiteAuthorityRepo
  }

  alias Beamlet.Actions.Storage.Schema.JournalAttempt

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
      descriptor: Profiles.authority(),
      database: authority,
      peer_database: journal,
      dataset_id: Ecto.UUID.generate()
    ]

    journal_opts = [
      descriptor: Profiles.journal(),
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
      authority_id: authority_opts[:dataset_id],
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
        evidence_id: evidence_id
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

  test "prepared siblings accept in reverse order without changing their dispatch scope",
       context do
    persistence = persistence(context)
    boot(persistence)
    op = %{operation("hold") | claims: %{}}
    {scope_id, persistence, [first, second]} = prepare_scoped(persistence, [op, op])

    assert {:ok, a} = Runtime.submit(op, persistence: persistence, prepared: first)
    assert_receive {:handler_started, worker_a, _}, 2000
    assert {:ok, b} = Runtime.submit(op, persistence: persistence, prepared: second)
    assert_receive {:handler_started, worker_b, _}, 2000
    send(worker_b, :release)
    assert_receive {:beamlet_operation, ^b, {:result, %{status: :ok}}}, 3000
    send(worker_a, :release)
    assert_receive {:beamlet_operation, ^a, {:result, %{status: :ok}}}, 3000

    assert {:ok, %{"epoch" => 0}} = DispatchScopes.current(SQLiteAuthorityRepo, scope_id)

    for ref <- [a, b] do
      assert {:ok, row} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
      assert row["operation"]["accepted_result"]["status"] == "ok"
      assert row["operation"]["history_seq"] == 2
    end
  end

  test "simultaneous sibling completion accepts both Operations", context do
    persistence = persistence(context)
    boot(persistence)
    op = %{operation("hold") | claims: %{}}
    {scope_id, persistence, prepared} = prepare_scoped(persistence, [op, op])

    refs =
      Enum.map(prepared, fn member ->
        {:ok, ref} = Runtime.submit(op, persistence: persistence, prepared: member)
        ref
      end)

    assert_receive {:handler_started, a, _}, 2000
    assert_receive {:handler_started, b, _}, 2000
    Enum.each([a, b], &send(&1, :release))

    for ref <- refs do
      assert_receive {:beamlet_operation, ^ref, {:result, %{status: :ok}}}, 3000
    end

    assert {:ok, %{"epoch" => 0}} = DispatchScopes.current(SQLiteAuthorityRepo, scope_id)
  end

  test "racing submissions of one prepared identity run once and never accept a losing claim",
       context do
    persistence = persistence(context)
    boot(persistence)
    op = operation("hold")
    {:ok, prepared} = Persistence.prepare(persistence, op)
    caller = self()

    jobs =
      for _ <- 1..2 do
        Task.async(fn ->
          Runtime.submit(op,
            persistence: persistence,
            prepared: prepared,
            owner: caller,
            sink: caller
          )
        end)
      end

    replies = Enum.map(jobs, &Task.await/1)
    assert Enum.any?(replies, &match?({:ok, _}, &1))
    assert_receive {:handler_started, worker, _}, 2000
    refute_receive {:handler_started, _, _}, 50
    {:ok, row} = OperationRecords.fetch(SQLiteAuthorityRepo, prepared["operation_id"])
    assert row["operation"]["accepted_result"] == nil
    send(worker, :release)
    assert_receive {:beamlet_operation, _, {:result, %{status: :ok}}}, 3000
    refute_receive {:beamlet_operation, _, {:result, _}}, 50
  end

  test "prepared submission binds full committed request and attempt; credentials stay transient",
       context do
    persistence = persistence(context)
    boot(persistence)
    op = %{operation("hold") | credentials: %{"api_key" => "transient-credential"}}
    {:ok, prepared} = Persistence.prepare(persistence, op)

    assert_raise ArgumentError, fn ->
      persistence
      |> Map.from_struct()
      |> Map.to_list()
      |> Keyword.put(:owner, %{})
      |> Persistence.new()
    end

    changed = %{op | payload: Map.put(op.payload, "marker", "changed")}

    assert {:error, :invalid_operation} =
             Runtime.submit(changed, persistence: persistence, prepared: prepared)

    wrong = Map.put(prepared, "attempt_id", Ecto.UUID.generate())

    assert {:error, :invalid_operation} =
             Runtime.submit(op, persistence: persistence, prepared: wrong)

    for {key, value} <- [
          {"description_digest", String.duplicate("0", 64)},
          {"lock_version", 1},
          {"attempt_version", 1},
          {"dispatch_scope_id", Ecto.UUID.generate()},
          {"dispatch_epoch", 1}
        ] do
      assert {:error, :invalid_operation} =
               Runtime.submit(op,
                 persistence: persistence,
                 prepared: Map.put(prepared, key, value)
               )
    end

    refute_received {:handler_started, _, _}

    assert {:ok, ref} = Runtime.submit(op, persistence: persistence, prepared: prepared)
    assert_receive {:handler_started, worker, _}, 2000

    assert {:error, :invalid_operation} =
             Runtime.submit(op, persistence: persistence, prepared: prepared)

    refute_received {:handler_started, _, _}
    send(worker, :release)
    assert_receive {:beamlet_operation, ^ref, {:result, %{status: :ok}}}, 3000
    assert {:ok, row} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
    refute inspect(row) =~ "transient-credential"
    ExecutorJournalRepo.stop()
    assert {:ok, evidence} = Runtime.evidence(persistence, ref.id, prepared["attempt_id"])
    assert evidence.journal == :unavailable
    assert evidence.authority["operation"]["accepted_result"]["status"] == "ok"
  end

  test "stale scope epoch cannot claim prepared work", context do
    persistence = persistence(context)
    boot(persistence)
    op = operation("hold")
    {scope_id, persistence, [prepared]} = prepare_scoped(persistence, [op])

    assert {:ok, _} =
             DispatchScopes.rotate(SQLiteAuthorityRepo, %{id: scope_id, expected_epoch: 0})

    assert {:ok, ref} = Runtime.submit(op, persistence: persistence, prepared: prepared)
    monitor = Process.monitor(ref.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 2000
    refute_received {:handler_started, _, _}
    assert {:ok, row} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
    assert row["attempt"]["dispatch_state"] == "prepared"
    assert row["operation"]["accepted_result"] == nil
  end

  for delta <- [0, -1] do
    @admit_delta delta
    test "durable admission counts credentials and identity envelope at delta #{delta}",
         context do
      persistence = persistence(context)
      boot(persistence)

      op = %{
        operation("hold", 5000, %{"marker" => String.duplicate("x", 1000)})
        | credentials: %{"token" => String.duplicate("y", 1000)}
      }

      {:ok, prepared} = Persistence.prepare(persistence, op)
      {:ok, endpoint, report} = Runtime.Directory.select(op)

      {:ok, _} =
        OperationRecords.claim_dispatch(SQLiteAuthorityRepo, %{
          operation_id: prepared["operation_id"],
          attempt_id: prepared["attempt_id"],
          expected_version: 0
        })

      durable = %{
        authority_id: persistence.authority_id,
        operation_id: prepared["operation_id"],
        attempt_id: prepared["attempt_id"],
        description_digest: prepared["description_digest"],
        executor_id: persistence.executor_id,
        executor_boot_id: persistence.executor_boot_id
      }

      message =
        {:admit, self(), prepared["operation_id"], prepared["attempt_id"], report.incarnation,
         report.lease, op, op.budget_ms, durable}

      bytes = :erlang.external_size(message)

      :sys.replace_state(Runtime.ExecutorGateway, fn state ->
        %{state | limits: %{state.limits | operation_bytes: bytes + @admit_delta}}
      end)

      send(endpoint, message)

      if @admit_delta == 0 do
        assert_receive {:handler_started, worker, _}, 2000
        send(worker, :release)
        assert_receive {:completed, _, _, %{status: :ok}, _}, 3000
      else
        assert_receive {:rejected, _, :ineligible}, 2000
        refute_received {:handler_started, _, _}

        assert {:error, :conflict} =
                 ExecutorJournal.fetch(
                   ExecutorJournalRepo,
                   persistence.authority_id,
                   prepared["attempt_id"]
                 )
      end
    end
  end

  for delta <- [0, -1] do
    @envelope_delta delta
    test "durable completion counts the entire receipt envelope at delta #{delta}", context do
      persistence = persistence(context)
      boot(persistence)
      marker = String.duplicate("x", 2000)

      {:ok, ref} =
        Runtime.submit(operation("hold", 5000, %{"marker" => marker}), persistence: persistence)

      assert_receive {:handler_started, worker, _}, 2000
      gateway = Process.whereis(Runtime.ExecutorGateway)
      state = :sys.get_state(gateway)
      [{key, entry}] = Enum.to_list(state.attempts)

      result = %Beamlet.Actions.Result{
        operation_id: ref.id,
        execution_id: entry.handle.id,
        status: :ok,
        source: :execution,
        value: %{"echo" => marker},
        metadata: %{gateway_progress_dropped: false, producer_progress_dropped: 0}
      }

      {:ok, receipt} = Persistence.receipt(entry.journal, result, %{"kind" => "returned"})
      bytes = :erlang.external_size({:completed, elem(key, 1), entry.handle, result, receipt})
      assert bytes > 1024

      :sys.replace_state(gateway, fn state ->
        %{state | limits: %{state.limits | result_bytes: bytes + @envelope_delta}}
      end)

      send(worker, :release)
      assert_receive {:beamlet_operation, ^ref, {:result, accepted}}, 3000

      if @envelope_delta == 0 do
        assert accepted.status == :ok
        assert accepted.value == %{"echo" => marker}
      else
        assert accepted.status == :error
        assert accepted.reason == :invalid_or_oversize_result
        assert accepted.value == nil
      end
    end
  end

  test "late terminal receipt is retained without replacing an accepted uncertain outcome",
       context do
    persistence = persistence(context)
    boot(persistence, cancel_ms: 400)

    {:ok, ref} =
      Runtime.submit(operation("hold", 5000, %{"trap" => true}), persistence: persistence)

    assert_receive {:handler_started, worker, _}, 2000
    gateway = Process.whereis(Runtime.ExecutorGateway)
    :sys.suspend(gateway)

    try do
      send(ref.pid, :deadline)
      assert_receive {:beamlet_operation, ^ref, {:result, %{status: :deadline}}}, 2000
      {:ok, before} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
      assert before["operation"]["accepted_evidence_id"] == nil
      send(worker, :release)
    after
      :sys.resume(gateway)
    end

    assert :ok = wait_late_evidence(ref.id)
    {:ok, after_late} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
    assert after_late["operation"]["accepted_result"]["status"] == "deadline"
    assert after_late["operation"]["accepted_evidence_id"] == nil
    refute_receive {:beamlet_operation, ^ref, {:result, _}}, 50
  end

  defp wait_late_evidence(id, attempts \\ 100)
  defp wait_late_evidence(_id, 0), do: :timeout

  defp wait_late_evidence(id, attempts) do
    {:ok, row} = OperationRecords.fetch(SQLiteAuthorityRepo, id)

    if SQLiteAuthorityRepo.aggregate(Beamlet.Actions.Storage.Schema.ExecutionEvidence, :count) > 0 do
      assert row["operation"]["accepted_result"]["status"] == "deadline"
      :ok
    else
      Process.sleep(5)
      wait_late_evidence(id, attempts - 1)
    end
  end

  test "failed authority acceptance produces no sink completion or status Result", context do
    persistence = persistence(context)
    boot(persistence)
    {:ok, ref} = Runtime.submit(operation("hold"), persistence: persistence)
    assert_receive {:handler_started, worker, _}, 2000
    SQLiteAuthorityRepo.stop()
    send(worker, :release)
    assert :ok = wait_accept_failure(ref)
    assert {:ok, %{result: nil, durable: %{accepted: false}}} = Runtime.status(ref)
    refute_received {:beamlet_operation, ^ref, {:result, _}}
  end

  defp wait_accept_failure(ref, attempts \\ 100)
  defp wait_accept_failure(_ref, 0), do: :timeout

  defp wait_accept_failure(ref, attempts) do
    case Runtime.status(ref) do
      {:ok, %{durable: %{accept_error: error}}} when not is_nil(error) ->
        :ok

      _ ->
        Process.sleep(5)
        wait_accept_failure(ref, attempts - 1)
    end
  end

  defp prepare_scoped(persistence, operations) do
    scope_id = Ecto.UUID.generate()
    {:ok, _} = DispatchScopes.create(SQLiteAuthorityRepo, %{id: scope_id})
    persistence = %{persistence | dispatch_scope_id: scope_id, dispatch_epoch: 0}

    prepared =
      Enum.map(operations, fn op ->
        {:ok, prepared} = Persistence.prepare(persistence, op)
        prepared
      end)

    {scope_id, persistence, prepared}
  end

  @tag :distributed
  test "named peer journals committed work and keeps credentials out of both databases",
       context do
    unless Node.alive?(), do: flunk("distributed tests require a named VM")
    persistence = persistence(context)
    paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

    {:ok, peer, remote} =
      :peer.start_link(%{
        name: String.to_atom("durable_b_#{System.unique_integer([:positive])}"),
        connection: :standard_io,
        args: [~c"+S", ~c"2:2", ~c"-setcookie", Atom.to_charlist(Node.get_cookie())] ++ paths,
        wait_boot: 10_000,
        shutdown: 3000
      })

    Process.unlink(peer)
    on_exit(fn -> if Process.alive?(peer), do: :peer.stop(peer) end)

    remote_opts =
      Keyword.put(context.journal_opts, :database, context.journal_opts[:database] <> ".remote")

    :ok = :peer.call(peer, Runtime.TestPeer, :boot_durable, [remote_opts, persistence, self()])
    start_supervised!({Runtime.SharedSupervisor, limits: [refresh_ms: 10, expiry_ms: 1000]})
    true = Node.connect(remote)
    Runtime.TestPeer.barrier("durable", 4000)
    credentials = %{"token" => "remote-only-credential"}

    {:ok, op} =
      Operation.new(
        kind: "durable",
        allowed_nodes: [remote],
        payload: %{"mode" => "credentials"},
        credentials: credentials
      )

    {:ok, prepared} = Persistence.prepare(persistence, op)
    assert {:ok, ref} = Runtime.submit(op, persistence: persistence, prepared: prepared)
    assert_receive {:credentials, ^remote, ^credentials}, 3000
    assert_receive {:beamlet_operation, ^ref, {:result, %{status: :ok}}}, 3000
    {:ok, row} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)

    {:ok, journal} =
      :peer.call(peer, ExecutorJournal, :fetch, [
        ExecutorJournalRepo,
        context.authority_id,
        prepared["attempt_id"]
      ])

    assert journal["state"] == "terminal"
    refute inspect({row, journal}) =~ "remote-only-credential"

    assert {:error, :invalid_operation} =
             Runtime.submit(op, persistence: persistence, prepared: prepared)

    refute_receive {:credentials, _, _}, 100
    assert_durable_peer_loss(peer, remote, persistence, context.authority_id)
  end

  defp assert_durable_peer_loss(peer, remote, persistence, authority_id) do
    {:ok, op} =
      Operation.new(kind: "durable", allowed_nodes: [remote], payload: %{"mode" => "hold"})

    await_peer_capacity(peer, op)
    {:ok, prepared} = Persistence.prepare(persistence, op)
    assert {:ok, ref} = Runtime.submit(op, persistence: persistence, prepared: prepared)
    assert_receive {:worker, worker}, 3000
    assert node(worker) == remote

    assert {:ok, %{"state" => "start_intent"}} =
             :peer.call(peer, ExecutorJournal, :fetch, [
               ExecutorJournalRepo,
               authority_id,
               prepared["attempt_id"]
             ])

    :ok = :peer.stop(peer)
    assert_receive {:beamlet_operation, ^ref, {:result, %{status: :uncertain}}}, 3000
    assert {:ok, row} = OperationRecords.fetch(SQLiteAuthorityRepo, ref.id)
    assert row["attempt"]["dispatch_state"] == "send_claimed"
    assert row["operation"]["accepted_result"]["status"] == "uncertain"

    assert {:error, :invalid_operation} =
             Runtime.submit(op, persistence: persistence, prepared: prepared)

    refute_receive {:worker, _}, 100
  end

  defp await_peer_capacity(peer, op) do
    deadline = System.monotonic_time(:millisecond) + 3000

    await_condition(
      fn ->
        state = :peer.call(peer, :sys, :get_state, [Runtime.ExecutorGateway])
        state.ready and map_size(state.tasks) == 0
      end,
      deadline
    )

    released_at = :peer.call(peer, System, :monotonic_time, [:millisecond])

    await_condition(
      fn ->
        case Runtime.Directory.select(op) do
          {:ok, _, report} -> report.lease > released_at
          :none -> false
        end
      end,
      deadline
    )
  end

  defp await_condition(condition, deadline) do
    unless condition.() do
      if System.monotonic_time(:millisecond) >= deadline,
        do: flunk("fresh remote capacity not observed")

      Process.sleep(5)
      await_condition(condition, deadline)
    end
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
