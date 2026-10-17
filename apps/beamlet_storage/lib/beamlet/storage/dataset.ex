defmodule Beamlet.Storage.Dataset do
  @moduledoc """
  Explicit installation/open boundary. `initialize/2` is for a new dataset only;
  `open/2` never migrates or creates a missing SQLite file. Both leave a linked
  Repo running on success and return its pid. Stop it with `repo.stop/0`.

  Options require `dataset_id` (canonical UUID), `database`, and, for SQLite,
  `peer_database` (the other role's absolute file path). Paths must be local,
  absolute and symlink-free. PostgreSQL provisioning is the host's responsibility.
  `restored_backup` is an explicit operational marker, not rollback detection.
  """
  alias Beamlet.Storage.{
    Codec,
    ExecutorJournalRepo,
    Migrations,
    PostgresAuthorityRepo,
    SQLiteAuthorityRepo
  }

  alias Ecto.Adapters.SQL

  def initialize(repo, opts), do: start(repo, opts, :initialize)
  def open(repo, opts), do: start(repo, opts, :open)

  defp start(repo, opts, mode) do
    with :ok <- validate(repo, opts),
         :ok <- authority_available(repo),
         :ok <- prepare_file(repo, opts, mode),
         {:ok, pid} <- repo.start_link(Keyword.put(opts, :log, false)) do
      finish_start(repo, pid, opts, mode)
    else
      {:error, reason}
      when reason in [:invalid_data, :dataset_missing, :dataset_exists, :path_alias, :conflict] ->
        {:error, reason}

      _ ->
        {:error, :storage_unavailable}
    end
  rescue
    _ -> {:error, :storage_unavailable}
  catch
    :exit, _ -> {:error, :storage_unavailable}
  end

  defp finish_start(repo, pid, opts, mode) do
    case safely(fn -> initialize_and_verify(repo, opts, mode) end) do
      :ok ->
        {:ok, pid}

      error ->
        repo.stop()
        error
    end
  end

  defp initialize_and_verify(repo, opts, mode) do
    with :ok <- maybe_initialize(repo, opts, mode), do: verify_metadata(repo, opts)
  end

  defp authority_available(ExecutorJournalRepo), do: :ok

  defp authority_available(repo) do
    other = if repo == SQLiteAuthorityRepo, do: PostgresAuthorityRepo, else: SQLiteAuthorityRepo
    if Process.whereis(other), do: {:error, :conflict}, else: :ok
  end

  defp validate(repo, opts) do
    if repo in [SQLiteAuthorityRepo, PostgresAuthorityRepo, ExecutorJournalRepo] and
         Keyword.keyword?(opts) and not Keyword.has_key?(opts, :name) and
         Codec.uuid?(opts[:dataset_id]) do
      if repo == PostgresAuthorityRepo, do: :ok, else: validate_paths(opts)
    else
      {:error, :invalid_data}
    end
  end

  defp validate_paths(opts) do
    a = opts[:database]
    b = opts[:peer_database]

    cond do
      Keyword.has_key?(opts, :url) -> {:error, :invalid_data}
      not valid_path?(a) or not valid_path?(b) -> {:error, :invalid_data}
      Path.expand(a) == Path.expand(b) -> {:error, :path_alias}
      same_file?(a, b) -> {:error, :path_alias}
      true -> :ok
    end
  end

  defp valid_path?(path) when is_binary(path) do
    Path.type(path) == :absolute and path != "/" and
      not String.contains?(path, <<0>>) and
      path
      |> Path.expand()
      |> Path.split()
      |> Enum.scan(&Path.join(&2, &1))
      |> Enum.all?(fn part ->
        case File.lstat(part) do
          {:ok, %{type: :symlink}} -> false
          {:error, :enoent} -> true
          {:ok, _} -> true
          _ -> false
        end
      end)
  end

  defp valid_path?(_), do: false

  defp same_file?(a, b) do
    case {File.stat(a), File.stat(b)} do
      {{:ok, x}, {:ok, y}} -> x.inode == y.inode and x.major_device == y.major_device
      _ -> false
    end
  end

  defp prepare_file(PostgresAuthorityRepo, _, _), do: :ok

  defp prepare_file(_, opts, :open) do
    if File.regular?(opts[:database]), do: :ok, else: {:error, :dataset_missing}
  end

  defp prepare_file(_, opts, :initialize) do
    case File.open(opts[:database], [:write, :exclusive, :binary]) do
      {:ok, io} -> File.close(io)
      {:error, :eexist} -> {:error, :dataset_exists}
      _ -> {:error, :storage_unavailable}
    end
  end

  defp maybe_initialize(_, _, :open), do: :ok

  defp maybe_initialize(repo, opts, :initialize) do
    # Refuse an already-installed PostgreSQL dataset, even with a matching ID.
    exists_sql =
      if repo == PostgresAuthorityRepo,
        do:
          "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = current_schema() AND table_name = 'storage_metadata'",
        else:
          "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'storage_metadata'"

    case SQL.query!(repo, exists_sql, [], log: false).rows do
      [[0]] ->
        {:ok, :ok} =
          Migrations.install_metadata(repo, opts[:dataset_id], role(repo))

        path = Application.app_dir(:beamlet_storage, "priv/#{role(repo)}_migrations")
        Code.require_file(Path.join(path, "1_#{role(repo)}_v1.exs"))

        migration =
          if role(repo) == "journal",
            do: Beamlet.Storage.Migrations.JournalV1,
            else: Beamlet.Storage.Migrations.AuthorityV1

        Ecto.Migrator.run(repo, [{1, migration}], :up,
          all: true,
          log: false,
          log_migrations_sql: false
        )

        :ok

      _ ->
        {:error, :dataset_exists}
    end
  end

  @doc """
  Format/identity/migration check of an already-running dataset: reads
  `storage_metadata` and `schema_migrations` only. It never migrates, creates or
  writes, and returns `:ok` or a safe refusal (`:dataset_missing`,
  `:dataset_mismatch`, `:schema_unsupported`, `:restored_backup`,
  `:storage_unavailable`).
  """
  def verify(repo, opts) when is_list(opts) do
    if Keyword.keyword?(opts) and Codec.uuid?(opts[:dataset_id]) and
         repo in [SQLiteAuthorityRepo, PostgresAuthorityRepo, ExecutorJournalRepo] do
      safely(fn -> verify_metadata(repo, opts) end)
    else
      {:error, :invalid_data}
    end
  end

  def verify(_, _), do: {:error, :invalid_data}

  defp verify_metadata(repo, opts) do
    case SQL.query(
           repo,
           "SELECT dataset_id, role, format_version, restored_backup FROM storage_metadata WHERE id = 1",
           [],
           log: false
         ) do
      {:ok, %{rows: [[id, stored_role, version, backup]]}} ->
        cond do
          id != opts[:dataset_id] or stored_role != role(repo) -> {:error, :dataset_mismatch}
          version != 1 -> {:error, :schema_unsupported}
          backup not in [false, 0] -> {:error, :restored_backup}
          true -> verify_migrations(repo)
        end

      _ ->
        {:error, :dataset_missing}
    end
  end

  defp verify_migrations(repo) do
    case SQL.query(repo, "SELECT version FROM schema_migrations ORDER BY version", [], log: false) do
      {:ok, %{rows: [[1]]}} -> :ok
      _ -> {:error, :schema_unsupported}
    end
  end

  defp role(ExecutorJournalRepo), do: "journal"
  defp role(_), do: "authority"

  defp safely(fun) do
    fun.()
  rescue
    _ -> {:error, :storage_unavailable}
  catch
    :exit, _ -> {:error, :storage_unavailable}
  end
end
