defmodule Beamlet.Runtime.AdmissionHandler do
  @moduledoc false
  @behaviour Beamlet.Actions.Handler

  def run(payload, context) do
    send(context.settings, {:handler_started, self(), payload})
    {:ok, %{"echo" => payload["marker"]}}
  end
end

defmodule Beamlet.Runtime.DurableAdmissionTest do
  @moduledoc """
  Host-level durable admission gates the Runtime submit and accept paths on a live
  probe of the real SQLite dataset, never on Repo readiness.
  """
  use ExUnit.Case, async: false

  alias Beamlet.Actions.Operation
  alias Beamlet.Runtime
  alias Beamlet.Runtime.Persistence
  alias Beamlet.Storage.{Admission, Dataset, ExecutorJournalRepo, SQLiteAuthorityRepo}

  setup do
    dir = Path.join(System.tmp_dir!(), "beamlet-admission-#{System.unique_integer([:positive])}")
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
      for repo <- [SQLiteAuthorityRepo, ExecutorJournalRepo] do
        try do
          if Process.whereis(repo), do: repo.stop()
        catch
          _, _ -> :ok
        end
      end

      File.rm_rf!(dir)
    end)

    %{
      dir: dir,
      authority_opts: authority_opts,
      authority_id: Ecto.UUID.generate(),
      executor_id: Ecto.UUID.generate()
    }
  end

  test "a durable submit is refused while admission is off and admitted after recovery", ctx do
    persistence =
      Persistence.new(
        authority_repo: SQLiteAuthorityRepo,
        journal_repo: ExecutorJournalRepo,
        authority_id: ctx.authority_id,
        executor_id: ctx.executor_id,
        executor_boot_id: Ecto.UUID.generate()
      )

    boot(persistence)

    start_supervised!(%{
      id: :admission,
      start:
        {Admission, :start_link,
         [[repo: SQLiteAuthorityRepo, dataset_id: ctx.authority_opts[:dataset_id]]]}
    })

    assert :admitted = Admission.status()

    # The write path is gone: the Repo is still registered-ready, admission is not.
    SQLiteAuthorityRepo.stop()
    assert {:refused, _reason} = Admission.status()

    assert {:error, :unavailable} = Runtime.submit(operation(), persistence: persistence)
    refute_receive {:handler_started, _, _}, 200

    # Recovery is a fresh probe, not a restart of the host.
    assert {:ok, _} = Dataset.open(SQLiteAuthorityRepo, ctx.authority_opts)
    assert :admitted = Admission.status()

    assert {:ok, ref} = Runtime.submit(operation(), persistence: persistence)
    assert_receive {:handler_started, _worker, _payload}, 2000
    assert is_binary(ref.id)
  end

  for form <- [:struct, :keyword] do
    @persistence_form form
    test "recorded admission failure refuses #{@persistence_form} persistence before preparation",
         ctx do
      persistence =
        Persistence.new(
          authority_repo: SQLiteAuthorityRepo,
          journal_repo: ExecutorJournalRepo,
          authority_id: ctx.authority_id,
          executor_id: ctx.executor_id,
          executor_boot_id: Ecto.UUID.generate()
        )

      boot(persistence)

      start_supervised!(%{
        id: :admission,
        start:
          {Admission, :start_link,
           [[repo: SQLiteAuthorityRepo, dataset_id: ctx.authority_opts[:dataset_id]]]}
      })

      assert :admitted = Admission.status()
      assert :ok = Admission.failure(:storage_outcome_unknown)
      before_count = SQLiteAuthorityRepo.aggregate(Beamlet.Storage.Schema.Operation, :count)

      input =
        if @persistence_form == :keyword,
          do: Enum.to_list(Map.from_struct(persistence)),
          else: persistence

      assert {:error, :unavailable} = Runtime.submit(operation(), persistence: input)

      assert SQLiteAuthorityRepo.aggregate(Beamlet.Storage.Schema.Operation, :count) ==
               before_count

      refute_receive {:handler_started, _, _}, 100
    end
  end

  defp boot(persistence) do
    {:ok, pid} =
      Runtime.SharedSupervisor.start_link(
        execution: true,
        handlers: %{"durable" => {Beamlet.Runtime.AdmissionHandler, self()}},
        pools: %{"cpu" => 1},
        persistence: persistence,
        limits: [
          refresh_ms: 10,
          expiry_ms: 300,
          retention_ms: 1000,
          cancel_ms: 50,
          admission_ms: 500
        ]
      )

    Process.unlink(pid)

    on_exit(fn -> if Process.alive?(pid), do: Supervisor.stop(pid) end)

    Runtime.TestPeer.barrier("durable")
    pid
  end

  defp operation do
    {:ok, operation} =
      Operation.new(
        kind: "durable",
        payload: %{"mode" => "echo", "marker" => "marker"},
        claims: %{"cpu" => 1},
        budget_ms: 5000
      )

    operation
  end
end
