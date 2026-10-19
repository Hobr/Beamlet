defmodule Beamlet.Storage.Artifacts do
  @moduledoc """
  同一数据集内的二进制制品存储。写入及事务内引用校验共享调用方事务；只存 SQL 内容，不访问外部对象存储，不做 GC。digest 唯一约束拒绝重复内容；按摘要复用已有记录由调用方负责。

  Dataset-local artifact content. `put/2` and `verify_references/2` must run
  inside the caller's dataset transaction (e.g. Ecto.Multi.run), so references
  and content roll back together. No filesystem/object-store effects or GC.
  """
  alias Beamlet.Storage.{Codec, Transaction}
  alias Beamlet.Storage.Schema.Artifact

  @typedoc "制品验证及读取的安全错误；事务外调用错误仍为 invalid_data。"
  @type error :: :invalid_data | :limit | :conflict | :artifact_missing | :storage_unavailable
  @typep fetched :: {:ok, Artifact.t()} | {:error, error()}
  @doc "构建制品插入校验：规范 UUID、摘要、大小与内容须一致，内容最多 16MiB；附加主键及摘要唯一约束。"
  @spec changeset(term()) :: Ecto.Changeset.t(Artifact.t())
  def changeset(attrs) do
    Artifact.changeset(%Artifact{}, attrs)
    |> Ecto.Changeset.unique_constraint(:id, name: :artifacts_pkey)
    |> Ecto.Changeset.unique_constraint(:id)
    |> Ecto.Changeset.unique_constraint(:digest)
  end

  @doc "在调用方事务内插入制品；无事务返回 invalid_data，重复 ID/摘要返回 conflict，不自动复用已有内容。驱动异常由外层 Transaction.write 分类。"
  @spec put(module(), term()) ::
          {:ok, Artifact.t()} | {:error, :invalid_data | :limit | :conflict}
  def put(repo, attrs) do
    cs = changeset(attrs)

    cond do
      not repo.in_transaction?() -> {:error, :invalid_data}
      not cs.valid? -> validation_error(cs)
      true -> insert(repo, cs)
    end
  end

  @spec validation_error(Ecto.Changeset.t()) :: {:error, :limit | :invalid_data}
  defp validation_error(cs) do
    if Enum.any?(cs.errors, fn {_, {message, _}} -> message == "limit" end),
      do: {:error, :limit},
      else: {:error, :invalid_data}
  end

  @spec insert(module(), Ecto.Changeset.t(Artifact.t())) ::
          {:ok, Artifact.t()} | {:error, :conflict}
  defp insert(repo, cs) do
    case repo.insert(cs, log: false) do
      {:ok, record} -> {:ok, record}
      {:error, _} -> {:error, :conflict}
    end
  end

  @doc "按规范 UUID 读取并复核内容摘要及大小；不存在返回 artifact_missing，读失败返回 storage_unavailable，损坏返回 invalid_data。"
  @spec fetch(module(), term()) :: fetched()
  def fetch(repo, id) do
    if Codec.uuid?(id) do
      Transaction.read(fn -> do_fetch(repo, id) end)
    else
      {:error, :invalid_data}
    end
  end

  @spec do_fetch(module(), String.t()) :: fetched()
  defp do_fetch(repo, id) do
    case repo.get(Artifact, id, log: false) do
      nil -> {:error, :artifact_missing}
      artifact -> validate_stored(artifact)
    end
  end

  @spec validate_stored(Artifact.t()) :: fetched()
  defp validate_stored(artifact) do
    attrs = Map.from_struct(artifact) |> Map.delete(:__meta__)
    if changeset(attrs).valid?, do: {:ok, artifact}, else: {:error, :invalid_data}
  end

  @doc "在调用方事务内逐项读取校验最多 1024 个制品 ID；无事务返回 invalid_data，超量返回 limit，遇首个失败停止。"
  @spec verify_references(module(), term()) :: :ok | {:error, error()}
  def verify_references(repo, ids) when is_list(ids) and length(ids) <= 1024 do
    if repo.in_transaction?() do
      Enum.reduce_while(ids, :ok, fn id, :ok -> verify_reference(repo, id) end)
    else
      {:error, :invalid_data}
    end
  end

  def verify_references(_, ids) when length(ids) > 1024, do: {:error, :limit}
  def verify_references(_, _), do: {:error, :invalid_data}

  @spec verify_reference(module(), term()) :: {:cont, :ok} | {:halt, {:error, error()}}
  defp verify_reference(repo, id) do
    case fetch(repo, id) do
      {:ok, _} -> {:cont, :ok}
      error -> {:halt, error}
    end
  end
end
