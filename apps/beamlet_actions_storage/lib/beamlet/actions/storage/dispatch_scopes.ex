defmodule Beamlet.Actions.Storage.DispatchScopes do
  @moduledoc "不透明派发作用域及 epoch 栅栏。先锁 scope 再锁 Operation；接受 Result 不锁 scope。轮换使旧 epoch 无法取得新派发许可，不代表已经派发的外部工作已停止。

Opaque dispatch epochs. Lock order is scope then Operation; acceptance never locks a scope."
  alias Beamlet.Actions.Storage.Records
  alias Beamlet.Actions.Storage.Schema.DispatchScope
  alias Beamlet.Actions.Storage.Schema.Execution
  alias Beamlet.Actions.Storage.Schema.Operation

  @typep reauthorization :: %{
           scope_id: String.t(),
           from_epoch: non_neg_integer(),
           to_epoch: non_neg_integer(),
           operation_id: String.t(),
           attempt_id: String.t(),
           description_digest: String.t(),
           expected_version: non_neg_integer(),
           attempt_version: non_neg_integer()
         }
  @spec create(module(), term()) :: Records.result(Records.object())
  @spec rotate(module(), term()) :: Records.result(Records.object())
  @spec create_in_transaction(module(), term()) :: Records.result(Records.object())
  @spec current(module(), term()) :: Records.result(Records.object())
  @spec read_current(module(), String.t()) :: Records.result(Records.object())
  @spec rotate_in_transaction(module(), term()) :: Records.result(Records.object())
  @spec validate_binding(term(), term()) :: :ok | {:error, :invalid_data}
  @spec check(module(), term(), term()) :: :ok | {:error, Records.error()}
  @spec reauthorize_in_transaction(module(), term()) :: Records.result(Records.object())
  @spec reauthorize(module(), reauthorization()) :: Records.result(Records.object())
  @spec eligible?(Operation.t() | nil, Execution.t() | nil, reauthorization()) :: boolean()
  @spec locked(module(), String.t(), :exclusive | :shared) :: Records.result(DispatchScope.t())

  import Ecto.Query
  alias Beamlet.Actions.Storage.Read
  alias Beamlet.Storage.Transaction

  @doc "以独立事务创建 id 对应的 epoch=0 作用域。"
  def create(repo, attrs),
    do: Records.transact(repo, fn -> create_in_transaction(repo, attrs) end)

  @doc "以独立事务按 id/expected_epoch 轮换，旧版本返回 stale_epoch。"
  def rotate(repo, attrs),
    do: Records.transact(repo, fn -> rotate_in_transaction(repo, attrs) end)

  @doc "在调用方同 Repo 事务中创建 epoch=0 作用域；事务外拒绝，不独立提交。"
  def create_in_transaction(repo, attrs) do
    Transaction.participate(repo, fn ->
      with {:ok, _} <- Records.fields(attrs, [:id], []),
           {:ok, _} <- Records.uuid(attrs.id),
           {:ok, record} <-
             Records.insert(
               repo,
               DispatchScope.changeset(%DispatchScope{}, %{id: attrs.id, epoch: 0})
             ) do
        {:ok, Records.plain(record)}
      end
    end)
  end

  @doc "校验 UUID 后读取作用域当前 id/epoch；缺失返回 conflict。"
  def current(repo, id) do
    with {:ok, _} <- Records.uuid(id) do
      Read.read(fn -> read_current(repo, id) end)
    end
  end

  defp read_current(repo, id) do
    with {:ok, record} <- Records.get(repo, DispatchScope, id), do: {:ok, Records.plain(record)}
  end

  @doc "在同 Repo 事务内锁定作用域并按 expected_epoch 加一；调用方负责错误回滚。"
  def rotate_in_transaction(repo, attrs) do
    Transaction.participate(repo, fn ->
      with {:ok, _} <- Records.fields(attrs, [:id, :expected_epoch], []),
           {:ok, _} <- Records.uuid(attrs.id),
           {:ok, _} <- Records.count(attrs.expected_epoch),
           {:ok, record} <- locked(repo, attrs.id, :exclusive),
           true <- record.epoch == attrs.expected_epoch do
        {1, _} =
          repo.update_all(
            from(s in DispatchScope, where: s.id == ^attrs.id),
            [set: [epoch: record.epoch + 1]],
            log: false
          )

        {:ok, %{"id" => attrs.id, "epoch" => record.epoch + 1}}
      else
        false -> {:error, :stale_epoch}
        error -> error
      end
    end)
  end

  @doc "scope id 与 epoch 须同时为空或同时有效；epoch 是非负整数。"
  def validate_binding(nil, nil), do: :ok

  def validate_binding(id, epoch) when not is_nil(id) and not is_nil(epoch) do
    with {:ok, _} <- Records.uuid(id), {:ok, _} <- Records.count(epoch), do: :ok
  end

  def validate_binding(_, _), do: {:error, :invalid_data}

  @doc "事务内以共享锁核对 scope/epoch；无绑定时通过，旧 epoch 返回 stale_epoch。"
  def check(_repo, nil, nil), do: :ok

  def check(repo, id, epoch) do
    with :ok <- validate_binding(id, epoch),
         {:ok, record} <- locked(repo, id, :shared) do
      if record.epoch == epoch, do: :ok, else: {:error, :stale_epoch}
    end
  end

  @doc "仅供显式继续：在外层事务中将仍 prepared、未接受且版本/摘要匹配的工作绑定到更高 epoch；已认领的未决工作拒绝。

Explicit continuation only: rebind a pending prepared identity after a rotation, in the caller transaction."
  def reauthorize_in_transaction(repo, attrs) do
    Transaction.participate(repo, fn ->
      with {:ok, _} <-
             Records.fields(
               attrs,
               [
                 :scope_id,
                 :from_epoch,
                 :to_epoch,
                 :operation_id,
                 :attempt_id,
                 :description_digest,
                 :expected_version,
                 :attempt_version
               ],
               []
             ),
           :ok <- validate_binding(attrs.scope_id, attrs.from_epoch),
           {:ok, _} <- Records.count(attrs.to_epoch),
           true <- attrs.to_epoch > attrs.from_epoch,
           {:ok, _} <- Records.uuid(attrs.operation_id),
           {:ok, _} <- Records.uuid(attrs.attempt_id),
           {:ok, _} <- Records.digest(attrs.description_digest),
           {:ok, _} <- Records.count(attrs.expected_version),
           {:ok, _} <- Records.count(attrs.attempt_version),
           :ok <- check(repo, attrs.scope_id, attrs.to_epoch) do
        reauthorize(repo, attrs)
      else
        false -> {:error, :invalid_data}
        error -> error
      end
    end)
  end

  defp reauthorize(repo, attrs) do
    query = from(o in Operation, where: o.id == ^attrs.operation_id)

    query =
      if repo.__adapter__() == Ecto.Adapters.Postgres, do: lock(query, "FOR UPDATE"), else: query

    operation = repo.one(query, log: false)
    attempt = repo.get(Execution, attrs.attempt_id, log: false)

    if eligible?(operation, attempt, attrs) do
      repo.update_all(
        from(o in Operation, where: o.id == ^attrs.operation_id),
        [set: [dispatch_epoch: attrs.to_epoch, lock_version: attrs.expected_version + 1]],
        log: false
      )

      {:ok,
       %{
         "operation_id" => attrs.operation_id,
         "lock_version" => attrs.expected_version + 1,
         "dispatch_scope_id" => attrs.scope_id,
         "dispatch_epoch" => attrs.to_epoch
       }}
    else
      {:error, :conflict}
    end
  end

  defp eligible?(nil, _, _), do: false
  defp eligible?(_, nil, _), do: false

  defp eligible?(operation, attempt, attrs) do
    operation.dispatch_scope_id == attrs.scope_id and operation.dispatch_epoch == attrs.from_epoch and
      operation.lock_version == attrs.expected_version and is_nil(operation.accepted_result) and
      operation.description_digest == attrs.description_digest and
      attempt.operation_id == operation.id and
      attempt.dispatch_state == "prepared" and attempt.lock_version == attrs.attempt_version
  end

  defp locked(repo, id, mode) do
    query = from(s in DispatchScope, where: s.id == ^id)

    query =
      case {repo.__adapter__(), mode} do
        {Ecto.Adapters.Postgres, :shared} -> lock(query, "FOR SHARE")
        {Ecto.Adapters.Postgres, :exclusive} -> lock(query, "FOR UPDATE")
        _ -> query
      end

    case repo.one(query, log: false) do
      nil -> {:error, :conflict}
      record -> {:ok, record}
    end
  end
end
