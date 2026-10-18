defmodule Beamlet.Server.DurableHostTest do
  use ExUnit.Case, async: false

  alias Beamlet.Actions.Storage.ExecutorJournalRepo
  alias Beamlet.Agent.Storage.SQLiteAuthorityRepo
  alias Beamlet.Node.Storage, as: Host
  alias Beamlet.Node.Storage.Operator
  alias Beamlet.Storage.Admission

  setup do
    dir =
      Path.join(System.tmp_dir!(), "beamlet-server-durable-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    storage = storage(dir)

    {:ok, %{authority: :installed, journal: :installed}} =
      Operator.initialize([:authority, :executor], storage)

    previous = Application.get_all_env(:beamlet_app_server)
    :ok = Application.stop(:beamlet_app_server)

    on_exit(fn ->
      Application.stop(:beamlet_app_server)

      for {key, _} <- Application.get_all_env(:beamlet_app_server),
          do: Application.delete_env(:beamlet_app_server, key)

      Application.put_all_env(beamlet_app_server: previous)

      for repo <- [SQLiteAuthorityRepo, ExecutorJournalRepo] do
        try do
          if Process.whereis(repo), do: repo.stop()
        catch
          _, _ -> :ok
        end
      end

      File.rm_rf!(dir)
      {:ok, _} = Application.ensure_all_started(:beamlet_app_server)
    end)

    %{dir: dir, storage: storage}
  end

  test "only the roles that need a dataset start one, and interaction needs no database" do
    assert {:ok, children} = Beamlet.Node.configuration(roles: [:interaction])
    refute Enum.any?(children, &durable_child?/1)

    assert {:ok, children} = Beamlet.Node.configuration(roles: [:authority, :executor])
    refute Enum.any?(children, &durable_child?/1)
  end

  test "library loading starts no Repo and no admission" do
    assert Process.whereis(SQLiteAuthorityRepo) == nil
    assert Process.whereis(ExecutorJournalRepo) == nil
    assert Process.whereis(Admission) == nil
    assert Process.whereis(Host) == nil

    {:ok, _} = Application.ensure_all_started(:beamlet_storage)
    assert Process.whereis(SQLiteAuthorityRepo) == nil
    assert Process.whereis(Admission) == nil
  end

  test "storage configuration is validated for the roles it must serve", ctx do
    assert {:ok, settings} =
             Beamlet.Server.configuration(node: [roles: [:authority]], storage: ctx.storage)

    assert settings[:storage].authority[:dataset_id] == ctx.storage[:dataset_id]
    assert settings[:storage].journal == nil

    assert {:ok, settings} =
             Beamlet.Server.configuration(node: [roles: [:executor]], storage: ctx.storage)

    assert settings[:storage].authority == nil
    assert settings[:storage].journal[:dataset_id] == ctx.storage[:journal][:dataset_id]

    assert {:ok, settings} = Beamlet.Server.configuration(node: [roles: [:authority]])
    assert settings[:storage] == nil

    for bad <- [
          Keyword.put(ctx.storage, :dataset_id, "not-a-uuid"),
          Keyword.put(ctx.storage, :executor_id, nil),
          Keyword.delete(ctx.storage, :journal),
          Keyword.put(ctx.storage, :database, "relative/authority.db"),
          Keyword.put(ctx.storage, :unknown, 1),
          Keyword.put(ctx.storage, :adapter, :mysql)
        ] do
      assert {:error, :invalid_server_configuration} =
               Beamlet.Server.configuration(node: [roles: [:authority, :executor]], storage: bad)
    end
  end

  test "authority-only opens the authority dataset and admits durable work", ctx do
    start_server([:authority], ctx.storage)

    assert Process.whereis(SQLiteAuthorityRepo)
    assert Process.whereis(ExecutorJournalRepo) == nil
    assert %{admission: :admitted, datasets: %{authority: :ready}} = Host.status()
    assert {:error, :journal_not_configured} = Host.runtime()

    # Registration readiness is unchanged and distinct from durable admission.
    assert {:ok, observation} = Beamlet.Node.observation()
    assert observation.services.authority == :ready
  end

  test "executor-only opens only the journal and starts no Agent authority", ctx do
    start_server([:executor], ctx.storage)

    assert Process.whereis(SQLiteAuthorityRepo) == nil
    assert Process.whereis(ExecutorJournalRepo)
    assert Process.whereis(Admission)
    assert Process.whereis(Beamlet.Agent.Registry) == nil
    assert Process.whereis(Beamlet.Agent.Agents) == nil
    assert {:error, :authority_not_configured} = Host.runtime()
    assert %{datasets: %{journal: :ready}} = Host.status()
  end

  test "authority and executor open both datasets and admit durable work", ctx do
    start_server([:authority, :executor], ctx.storage)

    assert Process.whereis(SQLiteAuthorityRepo)
    assert Process.whereis(ExecutorJournalRepo)
    assert :admitted = Admission.status()

    assert {:ok, runtime} = Host.runtime()
    assert runtime.authority_repo == SQLiteAuthorityRepo
    assert runtime.journal_repo == ExecutorJournalRepo
    assert runtime.executor_id == ctx.storage[:executor_id]
    assert {:ok, _boot_id} = Ecto.UUID.cast(runtime.executor_boot_id)
  end

  test "a dataset that is missing at boot refuses admission instead of recreating it", ctx do
    File.rm!(ctx.storage[:database])

    start_server([:authority], ctx.storage)

    assert %{
             admission: {:refused, :dataset_missing},
             datasets: %{authority: {:refused, :dataset_missing}}
           } =
             Host.status()

    refute File.exists?(ctx.storage[:database])
  end

  # The host re-validates its own environment at boot, so the test writes the same
  # trusted operator shape a deployment would.
  defp start_server(roles, storage) do
    :ok =
      Application.put_all_env(
        beamlet_app_server: [enabled: true, node: [roles: roles], storage: storage]
      )

    {:ok, _} = Application.ensure_all_started(:beamlet_app_server)
    :ok
  end

  # Node returns `{module, opts}` children; a storage child would name one.
  defp durable_child?({module, _opts}), do: durable_module?(module)
  defp durable_child?(%{start: {module, _, _}}), do: durable_module?(module)
  defp durable_child?(_child), do: false

  defp durable_module?(module) do
    module in [Beamlet.Node.Storage, Beamlet.Storage.Admission] or
      module in [SQLiteAuthorityRepo, ExecutorJournalRepo, Beamlet.Storage.Dataset]
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
end
