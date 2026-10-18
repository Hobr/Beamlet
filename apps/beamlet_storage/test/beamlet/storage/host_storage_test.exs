defmodule Beamlet.Storage.HostStorageTest do
  use ExUnit.Case, async: false

  alias Beamlet.Storage.{
    Admission,
    Dataset,
    ExecutorJournalRepo,
    Host,
    Operator,
    SQLiteAuthorityRepo
  }

  alias Ecto.Adapters.SQL

  setup do
    # A Repo that outlived a failed earlier test would be reused by name; start from
    # a known-empty VM state.
    stop_repos()

    dir =
      Path.join(System.tmp_dir!(), "beamlet-host-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    storage = storage(dir)

    on_exit(fn ->
      stop_repos()
      File.rm_rf!(dir)
    end)

    %{dir: dir, storage: storage}
  end

  test "the operator installs both datasets once and never recreates them", ctx do
    assert {:ok, %{authority: :installed, journal: :installed}} =
             Operator.initialize([:authority, :executor], ctx.storage)

    assert File.regular?(ctx.storage[:database])
    assert File.regular?(ctx.storage[:journal][:database])
    assert Process.whereis(SQLiteAuthorityRepo) == nil

    # A real dataset is never silently recreated or re-installed.
    assert {:error, {:authority, :dataset_exists}} =
             Operator.initialize([:authority, :executor], ctx.storage)
  end

  test "a missing dataset is refused instead of created on open", ctx do
    assert {:error, :dataset_missing} = Dataset.open(SQLiteAuthorityRepo, authority_opts(ctx))
    refute File.exists?(ctx.storage[:database])
  end

  test "newer format, mismatched identity and restored_backup are refused on open", ctx do
    for {sql, expected} <- [
          {"UPDATE storage_metadata SET format_version = 2 WHERE id = 1", :schema_unsupported},
          {"UPDATE storage_metadata SET dataset_id = '#{Ecto.UUID.generate()}' WHERE id = 1",
           :dataset_mismatch},
          {"UPDATE storage_metadata SET restored_backup = TRUE WHERE id = 1", :restored_backup}
        ] do
      dir = Path.join(ctx.dir, "case-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      storage = storage(dir)

      assert {:ok, %{authority: :installed}} = Operator.initialize([:authority], storage)
      assert {:ok, _} = Dataset.open(SQLiteAuthorityRepo, authority_opts(%{storage: storage}))
      assert {:ok, _} = SQL.query(SQLiteAuthorityRepo, sql, [], log: false)
      SQLiteAuthorityRepo.stop()

      assert {:error, ^expected} =
               Dataset.open(SQLiteAuthorityRepo, authority_opts(%{storage: storage}))
    end
  end

  test "admission is a live probe: refused when the write path is gone, admitted after recovery",
       ctx do
    assert {:ok, _} = Operator.initialize([:authority], ctx.storage)
    assert {:ok, _} = Dataset.open(SQLiteAuthorityRepo, authority_opts(ctx))
    start_supervised!(%{id: :admission, start: {Admission, :start_link, [admission(ctx)]}})

    assert :admitted = Admission.status()
    assert :ok = Admission.consult()

    # The probe writes and rolls back: no committed change, no business row.
    {:ok, %{rows: [[1, id, 0]]}} =
      SQL.query(
        SQLiteAuthorityRepo,
        "SELECT format_version, dataset_id, restored_backup FROM storage_metadata WHERE id = 1",
        [],
        log: false
      )

    assert id == ctx.storage[:dataset_id]

    assert {:error, {:authority, :dataset_exists}} =
             Operator.initialize([:authority], ctx.storage)

    SQLiteAuthorityRepo.stop()
    assert {:refused, _reason} = Admission.status()
    assert {:error, :durable_not_admitted} = Admission.consult()

    assert {:ok, _} = Dataset.open(SQLiteAuthorityRepo, authority_opts(ctx))
    assert :admitted = Admission.status()
    assert :ok = Admission.consult()
  end

  test "a failed durable write turns admission off until a fresh probe succeeds", ctx do
    assert {:ok, _} = Operator.initialize([:authority], ctx.storage)
    assert {:ok, _} = Dataset.open(SQLiteAuthorityRepo, authority_opts(ctx))
    start_supervised!(%{id: :admission, start: {Admission, :start_link, [admission(ctx)]}})

    assert :admitted = Admission.status()

    # A reported write failure is not a cached admission: the gate is off until the
    # real probe says the dataset accepts writes again.
    SQLiteAuthorityRepo.stop()
    Admission.failure(:storage_outcome_unknown)
    assert {:refused, _reason} = Admission.status()
    assert {:error, :durable_not_admitted} = Admission.consult()

    assert {:ok, _} = Dataset.open(SQLiteAuthorityRepo, authority_opts(ctx))
    assert :admitted = Admission.status()
    assert :admitted = Admission.status()
  end

  test "a reported write failure alone flips the gate, before any probe", ctx do
    assert {:ok, _} = Operator.initialize([:authority], ctx.storage)
    assert {:ok, _} = Dataset.open(SQLiteAuthorityRepo, authority_opts(ctx))
    start_supervised!(%{id: :admission, start: {Admission, :start_link, [admission(ctx)]}})

    assert :ok = Admission.consult()

    # The dataset is still writable here, so only a recorded failure can refuse the
    # gate: `consult` honours it without probing it away.
    :ok = Admission.failure(:storage_outcome_unknown)
    assert {:error, :durable_not_admitted} = Admission.consult()
    assert {:error, :durable_not_admitted} = Admission.consult()

    # The operator view does probe again, and a successful probe clears it.
    assert :admitted = Admission.status()
    assert :ok = Admission.consult()
  end

  test "a refused journal pauses admission even when the authority dataset is ready", ctx do
    # The operator installs both datasets and stops the Repos it started, so the host
    # below is the only opener. Then the journal file disappears (lost volume).
    assert {:ok, _} = Operator.initialize([:authority, :executor], ctx.storage)
    File.rm!(ctx.storage[:journal][:database])

    {:ok, settings} = Host.configuration([:authority, :executor], ctx.storage)

    start_supervised!(%{
      id: :host,
      start: {Host, :start_link, [[storage: settings, name: :journal_lost_host]]}
    })

    assert %{
             admission: {:refused, :dataset_missing},
             datasets: %{authority: :ready, journal: {:refused, :dataset_missing}}
           } = Host.status(:journal_lost_host)
  end

  test "a restored backup pauses admission with the operator-visible reason", ctx do
    assert {:ok, _} = Operator.initialize([:authority], ctx.storage)
    assert {:ok, _} = Dataset.open(SQLiteAuthorityRepo, authority_opts(ctx))

    {:ok, _} =
      SQL.query(
        SQLiteAuthorityRepo,
        "UPDATE storage_metadata SET restored_backup = TRUE WHERE id = 1",
        [],
        log: false
      )

    SQLiteAuthorityRepo.stop()

    {:ok, settings} =
      Host.configuration([:authority], ctx.storage)

    start_supervised!(%{
      id: :host,
      start: {Host, :start_link, [[storage: settings, name: :paused_host]]}
    })

    assert {:error, :storage_not_configured} = Host.status(:other_host)
    assert %{admission: {:refused, :restored_backup}} = Host.status(:paused_host)
  end

  defp stop_repos do
    for repo <- [SQLiteAuthorityRepo, ExecutorJournalRepo] do
      try do
        if Process.whereis(repo), do: repo.stop()
      catch
        _, _ -> :ok
      end
    end

    :ok
  end

  defp storage(dir) do
    [
      adapter: :sqlite,
      database: Path.join(dir, "authority.db"),
      dataset_id: Ecto.UUID.generate(),
      journal: [
        database: Path.join(dir, "journal.db"),
        dataset_id: Ecto.UUID.generate()
      ],
      executor_id: Ecto.UUID.generate()
    ]
  end

  defp authority_opts(ctx) do
    [
      database: ctx.storage[:database],
      peer_database: ctx.storage[:journal][:database],
      dataset_id: ctx.storage[:dataset_id]
    ]
  end

  defp admission(ctx) do
    [
      repo: SQLiteAuthorityRepo,
      dataset_id: ctx.storage[:dataset_id],
      name: Admission
    ]
  end
end
