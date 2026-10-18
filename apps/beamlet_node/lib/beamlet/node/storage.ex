defmodule Beamlet.Node.Storage do
  @moduledoc """
  Explicit durable-storage wiring for one VM host, started only by a host that
  configures storage. Interaction-only and library loading start nothing.

  `configuration/2` validates the operator's `:storage` block for the configured
  roles and `datasets/2` returns the dataset options the roles need: `:authority`
  needs the authority dataset, `:executor` needs the executor-local journal, and
  a role set without either (interaction-only) needs no database.

  `init/1` takes the normalized settings `configuration/2` returned (the daemon
  stores exactly that), plus an optional `:name` and `:executor_boot_id`.

  This process opens exactly those datasets and the default
  `Beamlet.Storage.Admission`. It never creates, migrates or repairs a dataset:
  `Beamlet.Node.Storage.Operator` is the explicit operator action for that. A missing,
  newer-format, mismatched or restored_backup dataset leaves the host running with
  that safe reason and durable admission off, so interaction-only work continues
  and no durable work is admitted until an operator resolves it.

  `runtime/1` returns the wiring `Beamlet.Agent`/`Beamlet.Runtime` callers pass as
  `durable:`/`persistence:`: opaque Repo handles, the configured executor identity
  and this boot's executor boot id. `status/1` reports admission and each dataset
  refusal with fresh resource and admission probes.
  """
  use GenServer

  alias Beamlet.Actions.Storage.ExecutorJournalRepo
  alias Beamlet.Agent.Storage.PostgresAuthorityRepo
  alias Beamlet.Agent.Storage.SQLiteAuthorityRepo
  alias Beamlet.Storage.Admission
  alias Beamlet.Storage.Codec
  alias Beamlet.Storage.Host

  @keys [
    :adapter,
    :database,
    :dataset_id,
    :journal,
    :executor_id,
    :hostname,
    :socket_dir,
    :port,
    :username,
    :password
  ]
  @journal_keys [:database, :dataset_id, :peer_database]

  @doc """
  Validates a trusted operator `:storage` keyword for `roles`:

      storage: [
        adapter: :sqlite,                 # default; :postgres is optional
        database: "/var/lib/beamlet/authority.db",
        dataset_id: "<authority dataset uuid>",
        journal: [
          database: "/var/lib/beamlet/journal.db",
          dataset_id: "<journal dataset uuid>"
        ],
        executor_id: "<stable executor uuid>"
      ]

  The authority block is required for `:authority`; the journal block for
  `:executor`. `executor_id` is the durable executor identity of this VM.
  """
  def configuration(roles, storage) do
    with {:ok, %{adapter: adapter} = datasets} <- datasets(roles, storage),
         {:ok, executor_id} <- uuid(storage[:executor_id]) do
      {:ok, Map.merge(datasets, %{adapter: adapter, executor_id: executor_id})}
    end
  end

  @doc "Dataset options the roles need, without requiring the executor identity."
  def datasets(roles, storage) when is_list(roles) and is_list(storage) do
    with true <- Keyword.keyword?(storage),
         true <- Enum.uniq(Keyword.keys(storage)) == Keyword.keys(storage),
         true <- Keyword.keys(storage) -- @keys == [],
         adapter when adapter in [:sqlite, :postgres] <- Keyword.get(storage, :adapter, :sqlite),
         {:ok, common} <- common(adapter, storage),
         {:ok, authority} <- authority_dataset(roles, adapter, storage, common),
         {:ok, journal} <- journal_dataset(roles, storage, common) do
      {:ok, %{adapter: adapter, authority: authority, journal: journal}}
    else
      _ -> {:error, :invalid_storage_configuration}
    end
  end

  def datasets(_, _), do: {:error, :invalid_storage_configuration}

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc """
  Durable wiring for Agent/Runtime callers:
  `{:ok, %{authority_repo:, journal_repo:, executor_id:, executor_boot_id:}}`, or
  `{:error, :storage_not_configured | :authority_not_configured |
  :journal_not_configured}`. It grants no admission; submit/accept consult
  `Beamlet.Storage.Admission` themselves.
  """
  def runtime(name \\ __MODULE__) do
    case Process.whereis(name) do
      nil -> {:error, :storage_not_configured}
      pid -> GenServer.call(pid, :runtime, 5000)
    end
  catch
    :exit, reason -> host_exit(reason)
  end

  @doc "Admission status plus each configured dataset's open state."
  def status(name \\ __MODULE__) do
    case Process.whereis(name) do
      nil ->
        {:error, :storage_not_configured}

      pid ->
        GenServer.call(pid, :status, 5000)
    end
  catch
    :exit, reason -> host_exit(reason)
  end

  # A configured host that is slow or shut down is not "not configured": operators
  # must not read a timeout as "this VM has no storage".
  defp host_exit({:timeout, _}), do: {:error, :storage_unavailable}
  defp host_exit(:timeout), do: {:error, :storage_unavailable}
  defp host_exit(_reason), do: {:error, :storage_unavailable}

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    settings = Keyword.fetch!(opts, :storage)
    boot_id = Keyword.get_lazy(opts, :executor_boot_id, fn -> Ecto.UUID.generate() end)
    {:ok, open(%{storage: settings, boot_id: boot_id, datasets: %{}, admission: nil})}
  end

  @impl true
  def handle_call(:runtime, _from, state) do
    authority = state.storage[:authority]
    journal = state.storage[:journal]

    reply =
      cond do
        is_nil(authority) ->
          {:error, :authority_not_configured}

        is_nil(journal) ->
          {:error, :journal_not_configured}

        true ->
          {:ok,
           %{
             authority_repo: authority_repo(state.storage.adapter),
             journal_repo: ExecutorJournalRepo,
             executor_id: state.storage.executor_id,
             executor_boot_id: state.boot_id
           }}
      end

    {:reply, reply, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, %{admission: Admission.status(), datasets: dataset_status(), boot_id: state.boot_id},
     state}
  end

  defp dataset_status do
    case Host.status(Beamlet.Node.Storage.Resources) do
      statuses when is_map(statuses) ->
        Map.new(statuses, fn
          {key, :admitted} -> {key, :ready}
          {key, {:error, reason}} -> {key, {:refused, reason}}
        end)

      error ->
        error
    end
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}

  defp open(state) do
    datasets =
      for {key, repo, opts} <- [
            {:authority, authority_repo(state.storage.adapter), state.storage[:authority]},
            {:journal, ExecutorJournalRepo, state.storage[:journal]}
          ],
          opts != nil,
          do: %{key: key, repo: repo, options: opts}

    {:ok, host} = Host.start_link(name: Beamlet.Node.Storage.Resources, datasets: datasets)
    statuses = Host.status(Beamlet.Node.Storage.Resources)

    refused =
      Enum.find_value(statuses, fn
        {_, {:error, reason}} -> reason
        _ -> nil
      end)

    gate = Enum.find(datasets, &(&1.key == :authority)) || List.first(datasets)

    admission =
      if gate do
        {:ok, pid} =
          Admission.start_link(
            [
              repo: gate.repo,
              reason: refused,
              resources: Enum.map(datasets -- [gate], &{&1.repo, &1.options})
            ] ++ gate.options
          )

        pid
      end

    %{state | datasets: host, admission: admission}
  end

  @impl true
  def terminate(_, state) do
    if state.admission && Process.alive?(state.admission), do: GenServer.stop(state.admission)
    if Process.alive?(state.datasets), do: GenServer.stop(state.datasets)
  end

  defp common(:sqlite, storage) do
    with {:ok, authority} <- absolute(storage[:database]),
         {:ok, journal} <- absolute(get_in(storage, [:journal, :database])),
         true <- Path.expand(authority) != Path.expand(journal) do
      {:ok, %{authority_database: authority, journal_database: journal, peers: true}}
    else
      _ -> {:error, :invalid_storage_configuration}
    end
  end

  defp common(:postgres, storage) do
    with true <- is_binary(storage[:database]) and storage[:database] != "",
         true <- connectable?(storage),
         {:ok, journal} <- absolute(get_in(storage, [:journal, :database])),
         {:ok, peer} <- absolute(get_in(storage, [:journal, :peer_database])),
         true <- Path.expand(journal) != Path.expand(peer) do
      {:ok, %{authority_database: storage[:database], journal_database: journal, peers: peer}}
    else
      _ -> {:error, :invalid_storage_configuration}
    end
  end

  defp connectable?(storage) do
    host = is_binary(storage[:hostname]) or is_binary(storage[:socket_dir])
    port = is_nil(storage[:port]) or (is_integer(storage[:port]) and storage[:port] in 1..65_535)
    user = is_nil(storage[:username]) or is_binary(storage[:username])
    password = is_nil(storage[:password]) or is_binary(storage[:password])
    host and port and user and password
  end

  defp authority_dataset(roles, adapter, storage, common) do
    if :authority in roles do
      with {:ok, id} <- uuid(storage[:dataset_id]) do
        {:ok,
         [descriptor: Beamlet.Agent.Storage.Profiles.authority(), dataset_id: id] ++
           authority_opts(adapter, storage, common)}
      end
    else
      {:ok, nil}
    end
  end

  defp authority_opts(:sqlite, _storage, common) do
    [database: common.authority_database, peer_database: common.journal_database]
  end

  defp authority_opts(:postgres, storage, common) do
    [database: common.authority_database]
    |> put_present(:hostname, storage[:hostname])
    |> put_present(:socket_dir, storage[:socket_dir])
    |> put_present(:port, storage[:port])
    |> put_present(:username, storage[:username])
    |> put_present(:password, storage[:password])
  end

  defp journal_dataset(roles, storage, common) do
    if :executor in roles do
      journal = Keyword.get(storage, :journal, [])

      with true <- Keyword.keyword?(journal) and Keyword.keys(journal) -- @journal_keys == [],
           {:ok, id} <- uuid(journal[:dataset_id]),
           {:ok, peer} <- journal_peer(journal, common) do
        {:ok,
         [
           descriptor: Beamlet.Actions.Storage.Profiles.journal(),
           dataset_id: id,
           database: common.journal_database,
           peer_database: peer
         ]}
      else
        _ -> {:error, :invalid_storage_configuration}
      end
    else
      {:ok, nil}
    end
  end

  # `common/2` only ever yields `peers: true` (SQLite, journal peers with the
  # authority file) or `peers: <absolute binary>` (PostgreSQL), so no third
  # fallback clause exists; an unknown adapter already failed in `common/2`.
  defp journal_peer(_journal, %{peers: true, authority_database: authority}), do: {:ok, authority}
  defp journal_peer(_journal, %{peers: peer}) when is_binary(peer), do: {:ok, peer}

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)

  defp uuid(value) when is_binary(value) do
    if Codec.uuid?(value), do: {:ok, value}, else: {:error, :invalid_storage_configuration}
  end

  defp uuid(_), do: {:error, :invalid_storage_configuration}

  defp absolute(path) when is_binary(path) do
    if Path.type(path) == :absolute and path != "/" and not String.contains?(path, <<0>>),
      do: {:ok, path},
      else: {:error, :invalid_storage_configuration}
  end

  defp absolute(_), do: {:error, :invalid_storage_configuration}

  defp authority_repo(:postgres), do: PostgresAuthorityRepo
  defp authority_repo(:sqlite), do: SQLiteAuthorityRepo
end
