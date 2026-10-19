defmodule Beamlet.Storage.Dataset do
  @moduledoc """
  数据集 format3 的显式安装与打开边界。initialize 仅安装全新目标；open 不创建缺失 SQLite 文件，也不迁移或修复。成功返回 {:ok, linked_pid}，调用方负责 repo.stop/0。失败仅关闭本次启动的 Repo，已注册 Repo 返回 conflict。选项必须包含可信 descriptor、规范 UUID dataset_id 和 database；SQLite 还需绝对、无符号链接且互不别名的 peer_database。PostgreSQL 数据库由宿主预先创建。restored_backup 是显式运维标记，不是自动回滚检测。

  Explicit installation/open boundary. `initialize/2` is for a new dataset only;
  `open/2` never migrates or creates a missing SQLite file. Both leave a linked
  Repo running on success and return its pid. Stop it with `repo.stop/0`.

  Options require `descriptor` (see `Installation`), `dataset_id` (canonical UUID), `database`, and, for SQLite,
  `peer_database` (an explicitly isolated peer path). Paths must be local,
  absolute and symlink-free. PostgreSQL provisioning is the host's responsibility.
  `restored_backup` is an explicit operational marker, not rollback detection.
  """
  alias Beamlet.Storage.{Codec, Installation, Migrations}

  alias Ecto.Adapters.SQL
  alias Exqlite.Sqlite3

  @typedoc "数据集拒绝原因：缺失、已存在、路径别名、身份不符、清单不支持、恢复备份或不可用等；不自动修复。

Dataset refusal classifications; opening never initializes or repairs existing data."
  @type error ::
          :invalid_data
          | :dataset_missing
          | :dataset_exists
          | :path_alias
          | :conflict
          | :dataset_mismatch
          | :schema_unsupported
          | :restored_backup
          | :storage_unavailable
  @typedoc "含可信安装描述符和数据集身份的显式适配器连接选项；禁止 name/url 覆盖注册与连接策略。

Explicit adapter connection options with a trusted installation descriptor."
  @type options :: [
          {:descriptor, Installation.t()}
          | {:dataset_id, String.t()}
          | {:database, String.t()}
          | {:peer_database, String.t()}
          | {atom(), term()}
        ]
  @typep mode :: :initialize | :open
  @typep verification :: :ok | {:error, error()}
  @typep rows :: [[term()]]
  @typep reader :: (String.t() -> {:ok, rows()} | {:error, term()})
  @doc "显式安装全新数据集并返回链接的 Repo PID。SQLite 使用独占创建，父目录须已存在；PostgreSQL 须预先置备空数据库。已有目标拒绝，失败安装可能留下不完整目标，不自动删除或重试。"
  @spec initialize(module(), term()) :: {:ok, pid()} | {:error, error()}
  def initialize(repo, opts), do: start(repo, opts, :initialize)
  @doc "只打开完整匹配的现有数据集，成功返回链接 PID，由调用方关闭。SQLite 在可写启动前做只读预检；旧格式、缺失或不完整安装均拒绝，不修复。"
  @spec open(module(), term()) :: {:ok, pid()} | {:error, error()}
  def open(repo, opts), do: start(repo, opts, :open)

  @spec start(module(), term(), mode()) :: {:ok, pid()} | {:error, error()}
  defp start(repo, opts, mode) do
    with :ok <- validate(repo, opts),
         :ok <- available(repo),
         :ok <- prepare_file(repo, opts, mode),
         :ok <- preflight(repo, opts, mode),
         {:ok, pid} <- repo.start_link(Keyword.put(opts, :log, false)) do
      finish_start(repo, pid, opts, mode)
    else
      {:error, reason}
      when reason in [
             :invalid_data,
             :dataset_missing,
             :dataset_exists,
             :path_alias,
             :conflict,
             :dataset_mismatch,
             :schema_unsupported,
             :restored_backup
           ] ->
        {:error, reason}

      _ ->
        {:error, :storage_unavailable}
    end
  rescue
    _ -> {:error, :storage_unavailable}
  catch
    :exit, _ -> {:error, :storage_unavailable}
  end

  @spec finish_start(module(), pid(), options(), mode()) :: {:ok, pid()} | {:error, error()}
  defp finish_start(repo, pid, opts, mode) do
    case safely(fn -> initialize_and_verify(repo, opts, mode) end) do
      :ok ->
        {:ok, pid}

      error ->
        repo.stop()
        error
    end
  end

  @spec initialize_and_verify(module(), options(), mode()) :: verification()
  defp initialize_and_verify(repo, opts, mode) do
    with :ok <- maybe_initialize(repo, opts, mode), do: verify_metadata(repo, opts)
  end

  @spec available(module()) :: :ok | {:error, :conflict}
  defp available(repo) do
    if Process.whereis(repo), do: {:error, :conflict}, else: :ok
  end

  @spec validate(module(), term()) :: verification()
  defp validate(repo, opts) do
    with true <- Keyword.keyword?(opts),
         true <- not Keyword.has_key?(opts, :name) and not Keyword.has_key?(opts, :url),
         true <- Codec.uuid?(opts[:dataset_id]),
         :ok <- Installation.validate(opts[:descriptor]),
         true <- repo.__adapter__() in [Ecto.Adapters.SQLite3, Ecto.Adapters.Postgres] do
      if postgres?(repo), do: :ok, else: validate_paths(opts)
    else
      _ -> {:error, :invalid_data}
    end
  rescue
    _ -> {:error, :invalid_data}
  end

  @spec postgres?(module()) :: boolean()
  defp postgres?(repo), do: repo.__adapter__() == Ecto.Adapters.Postgres

  @spec validate_paths(keyword()) :: verification()
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

  @spec valid_path?(term()) :: boolean()
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

  @spec same_file?(String.t(), String.t()) :: boolean()
  defp same_file?(a, b) do
    case {File.stat(a), File.stat(b)} do
      {{:ok, x}, {:ok, y}} -> x.inode == y.inode and x.major_device == y.major_device
      _ -> false
    end
  end

  @spec prepare_file(module(), options(), mode()) :: verification()
  defp prepare_file(repo, opts, mode) do
    if postgres?(repo), do: :ok, else: prepare_sqlite_file(opts, mode)
  end

  @spec prepare_sqlite_file(options(), mode()) :: :ok | {:error, term()}
  defp prepare_sqlite_file(opts, :open) do
    if File.regular?(opts[:database]), do: :ok, else: {:error, :dataset_missing}
  end

  defp prepare_sqlite_file(opts, :initialize) do
    case File.open(opts[:database], [:write, :exclusive, :binary]) do
      {:ok, io} -> File.close(io)
      {:error, :eexist} -> {:error, :dataset_exists}
      _ -> {:error, :storage_unavailable}
    end
  end

  @spec preflight(module(), options(), mode()) :: :ok | {:error, term()}
  defp preflight(_, _, :initialize), do: :ok

  defp preflight(repo, opts, :open) do
    if postgres?(repo) do
      :ok
    else
      with {:ok, conn} <- Sqlite3.open(opts[:database], mode: :readonly) do
        try do
          verify_rows(opts, fn sql -> read_raw(conn, sql) end)
        after
          Sqlite3.close(conn)
        end
      end
    end
  end

  @spec read_raw(reference(), String.t()) :: {:ok, rows()} | {:error, term()}
  defp read_raw(conn, sql) do
    with {:ok, statement} <- Sqlite3.prepare(conn, sql) do
      try do
        Sqlite3.fetch_all(conn, statement)
      after
        Sqlite3.release(conn, statement)
      end
    end
  end

  @spec maybe_initialize(module(), options(), mode()) :: verification()
  defp maybe_initialize(_, _, :open), do: :ok

  defp maybe_initialize(repo, opts, :initialize) do
    sql =
      if postgres?(repo),
        do:
          "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = current_schema() AND table_type = 'BASE TABLE'",
        else:
          "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"

    case SQL.query!(repo, sql, [], log: false).rows do
      [[0]] ->
        with {:ok, :ok} <- Migrations.install_metadata(repo, opts[:dataset_id], opts[:descriptor]),
             do: Migrations.install(repo, opts[:descriptor])

      _ ->
        {:error, :dataset_exists}
    end
  end

  @doc "只读校验已运行 Repo 的身份、format3、profile、完整清单、安装完成标记及迁移 ID；不迁移、不探测写入。

Read-only identity/format/profile/complete manifest/migration verification."
  @spec verify(module(), term()) :: verification()
  def verify(repo, opts) do
    with :ok <- validate(repo, opts), do: safely(fn -> verify_metadata(repo, opts) end)
  end

  @spec verify_metadata(module(), options()) :: verification()
  defp verify_metadata(repo, opts) do
    verify_rows(opts, fn sql ->
      case SQL.query(repo, sql, [], log: false) do
        {:ok, %{rows: rows}} -> {:ok, rows}
        {:error, reason} -> {:error, read_error(reason)}
      end
    end)
  end

  @spec read_error(term()) :: :dataset_missing | :schema_unsupported | :storage_unavailable
  defp read_error(%Postgrex.Error{postgres: %{code: :undefined_table}}), do: :dataset_missing
  defp read_error(%Postgrex.Error{postgres: %{code: :undefined_column}}), do: :schema_unsupported
  defp read_error(%Exqlite.Error{message: message}), do: read_error(message)

  defp read_error(message) when is_binary(message) do
    cond do
      String.contains?(message, "no such table") -> :dataset_missing
      String.contains?(message, "no such column") -> :schema_unsupported
      true -> :storage_unavailable
    end
  end

  defp read_error(_), do: :storage_unavailable

  @spec verify_rows(options(), reader()) :: verification()
  defp verify_rows(opts, read) do
    # 先只读判断格式，避免旧库因启动可写 SQLite 连接产生 WAL 或被误当成待升级库。
    # Read format first: old metadata has different columns, and must be refused
    # before opening a writable SQLite connection or inspecting business tables.
    with {:ok, [[3]]} <- read.("SELECT format_version FROM storage_metadata WHERE id = 1"),
         {:ok, [[id, profile, backup, manifest, installed]]} <-
           read.(
             "SELECT dataset_id, profile, restored_backup, manifest, installed FROM storage_metadata WHERE id = 1"
           ) do
      cond do
        id != opts[:dataset_id] or profile != opts[:descriptor].profile ->
          {:error, :dataset_mismatch}

        backup not in [false, 0] ->
          {:error, :restored_backup}

        installed not in [true, 1] ->
          {:error, :schema_unsupported}

        manifest != Installation.manifest(opts[:descriptor]) ->
          {:error, :schema_unsupported}

        true ->
          verify_migrations(opts[:descriptor], read)
      end
    else
      {:ok, _} ->
        {:error, :schema_unsupported}

      {:error, reason}
      when reason in [:dataset_missing, :schema_unsupported, :storage_unavailable] ->
        {:error, reason}

      {:error, reason} ->
        {:error, read_error(reason)}
    end
  end

  @spec verify_migrations(Installation.t(), reader()) :: :ok | {:error, :schema_unsupported}
  defp verify_migrations(descriptor, read) do
    expected = Enum.map(descriptor.migrations, &[&1.id])

    case read.("SELECT version FROM schema_migrations ORDER BY version") do
      {:ok, ^expected} -> :ok
      _ -> {:error, :schema_unsupported}
    end
  end

  @spec safely((-> value)) :: value | {:error, :storage_unavailable} when value: var
  defp safely(fun) do
    fun.()
  rescue
    _ -> {:error, :storage_unavailable}
  catch
    :exit, _ -> {:error, :storage_unavailable}
  end
end
