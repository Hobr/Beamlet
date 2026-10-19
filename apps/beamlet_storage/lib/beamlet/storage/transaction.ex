defmodule Beamlet.Storage.Transaction do
  @moduledoc """
  存储事务与安全错误分类边界。SQLite 写事务使用 immediate 锁，普通读保持 deferred。write 拥有提交/回滚，participate 仅参与同 Repo 的已有事务。未分类驱动写失败保守返回 storage_outcome_unknown；调用方须按稳定身份核对结果，不得自动重试外部副作用。

  Internal storage transaction boundary. Writes take SQLite's immediate lock;
  ordinary Repo reads remain deferred. No retries or external effects are added.
  A driver failure during a write is conservatively outcome-unknown: reconcile
  using stable identities before attempting any external work.
  """
  @deterministic_violations [
    :check_violation,
    :not_null_violation,
    :foreign_key_violation,
    :restrict_violation,
    :exclusion_violation,
    :datatype_mismatch,
    :invalid_text_representation,
    :string_data_right_truncation,
    :numeric_value_out_of_range
  ]

  @doc """
  只在同 Repo 已有事务中调用参与者，否则返回 transaction_required。返回值原样传递：参与者返回错误不会自动回滚，调用方必须 rollback 或通过 Ecto.Multi 组合。

  Run a participant only within an existing caller-owned transaction.
  The participant validates its domain inputs and must not commit or perform
  external effects. Return values are passed through; callers must rollback on
  participant failure (or compose via Ecto.Multi). No nested transaction is made.
  """
  @typedoc "写入错误分类；storage_outcome_unknown 不代表确定未提交，不允许自动重试。

Safe write classification; an unknown outcome permits no automatic retry."
  @type write_error :: :conflict | :invalid_data | :storage_outcome_unknown
  @typep load_error :: %ArgumentError{message: String.t()}
  @typep repo_error :: %RuntimeError{message: String.t()}
  @spec participate(module(), (-> value)) :: value | {:error, :transaction_required}
        when value: var
  def participate(repo, fun) when is_function(fun, 0) do
    if repo.in_transaction?(), do: fun.(), else: {:error, :transaction_required}
  end

  @doc "运行拥有提交/回滚权的事务函数或 Ecto.Multi，保留 Ecto 的成功及 rollback/Multi 失败结果。函数返回 {:error, reason} 本身仍可提交，要求回滚时必须 repo.rollback/1。驱动写失败分类为 conflict、invalid_data 或 storage_outcome_unknown。"
  @spec write(module(), (-> value) | (module() -> value)) :: {:ok, value} | {:error, term()}
        when value: var
  @spec write(module(), Ecto.Multi.t()) ::
          {:ok, map()} | {:error, term()} | {:error, term(), term(), map()}
  def write(repo, multi_or_fun) do
    opts = [timeout: 5000, log: false]

    opts =
      if repo.__adapter__() == Ecto.Adapters.SQLite3,
        do: Keyword.put(opts, :mode, :immediate),
        else: opts

    try do
      repo.transaction(multi_or_fun, opts)
    rescue
      error in RuntimeError -> unavailable_repo(error, :storage_outcome_unknown, __STACKTRACE__)
      _ in [DBConnection.ConnectionError] -> {:error, :storage_outcome_unknown}
      error in [Exqlite.Error] -> {:error, classify_sqlite(error)}
      error in [Postgrex.Error] -> {:error, classify_postgres(error)}
    catch
      :exit, _ -> {:error, :storage_outcome_unknown}
    end
  end

  # 只有确定的约束拒绝才可确认回滚；断连可能发生在提交前后，必须保留结果未知。
  # A rejected statement aborts and rolls back the whole transaction, so the write
  # set is provably absent. Connection loss and unclassified driver errors stay
  # outcome-unknown: the client cannot prove the commit did not happen.
  @spec classify_sqlite(Exqlite.Error.t()) :: write_error()
  defp classify_sqlite(%Exqlite.Error{message: message}) when is_binary(message) do
    cond do
      String.contains?(message, "UNIQUE constraint") ->
        :conflict

      String.contains?(message, [
        "CHECK constraint",
        "NOT NULL constraint",
        "FOREIGN KEY",
        "datatype mismatch"
      ]) ->
        :invalid_data

      true ->
        :storage_outcome_unknown
    end
  end

  defp classify_sqlite(_), do: :storage_outcome_unknown

  @spec classify_postgres(Postgrex.Error.t()) :: write_error()
  defp classify_postgres(%Postgrex.Error{postgres: %{code: code}}) do
    cond do
      code == :unique_violation -> :conflict
      code in @deterministic_violations -> :invalid_data
      true -> :storage_outcome_unknown
    end
  end

  defp classify_postgres(_), do: :storage_outcome_unknown

  @doc "执行读取并将驱动/Repo 不可用规范为 storage_unavailable；仅精确匹配基础 JSON 类型的 Ecto struct_load! 失败转 invalid_data，其他编程异常保留。"
  @spec read((-> value)) :: value | {:error, :storage_unavailable | :invalid_data} when value: var
  def read(fun) do
    fun.()
  rescue
    error in RuntimeError ->
      unavailable_repo(error, :storage_unavailable, __STACKTRACE__)

    error in ArgumentError ->
      invalid_json_load(error, __STACKTRACE__)

    _ in [DBConnection.ConnectionError, Exqlite.Error, Postgrex.Error] ->
      {:error, :storage_unavailable}
  catch
    :exit, _ -> {:error, :storage_unavailable}
  end

  # Ecto raises when our strict JSON type refuses corrupted stored bytes. Do not
  # leak the raw field in that exception, or hide unrelated argument/programming errors.
  @spec invalid_json_load(load_error(), Exception.stacktrace()) :: {:error, :invalid_data}
  defp invalid_json_load(error, [{Ecto.Repo.Queryable, :struct_load!, _, _} | _] = stacktrace) do
    if String.starts_with?(error.message, "cannot load ") and
         String.contains?(error.message, " as type #Beamlet.Storage.JSON<"),
       do: {:error, :invalid_data},
       else: reraise(error, stacktrace)
  end

  defp invalid_json_load(error, stacktrace), do: reraise(error, stacktrace)

  @spec unavailable_repo(repo_error(), reason, Exception.stacktrace()) :: {:error, reason}
        when reason: var
  defp unavailable_repo(error, reason, stacktrace) do
    if String.starts_with?(error.message, "could not lookup Ecto repo "),
      do: {:error, reason},
      else: reraise(error, stacktrace)
  end
end
