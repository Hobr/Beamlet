defmodule Beamlet.Storage.References do
  @moduledoc "识别 JSON 信封中的 artifact_id、artifact_ids、artifact_refs 字符串键并校验同数据集制品。调用方先用 Codec/领域校验约束信封大小及形状；此遍历本身不提供深度或节点预算。事务写入使用 verify；只读重建使用 verify_read。

Dataset-local artifact reference verification for persisted JSON envelopes."
  alias Beamlet.Storage.Artifacts

  @doc "收集调用方已约束的 JSON 中制品身份，不去重也不校验 UUID；列表键值不是列表时返回 invalid_data。

Collect artifact identities from a bounded JSON envelope."
  @typep collected :: {:ok, [term()]} | {:error, :invalid_data}
  @typep verified :: :ok | {:error, Artifacts.error()}
  @spec ids(term()) :: collected()
  def ids(value), do: collect(value)

  @doc "收集并去重引用后调用事务内制品校验；须处于同 Repo 事务，数量上限按去重后 1024 个计算。"
  @spec verify(module(), term()) :: verified()
  def verify(repo, value) do
    with {:ok, ids} <- collect(value), do: Artifacts.verify_references(repo, Enum.uniq(ids))
  end

  @doc "只读重建时去重并读取校验引用制品，不要求写事务；缺失返回 artifact_missing，损坏返回 invalid_data。

Verify immutable dataset content during read-only reconstruction, without a write transaction."
  @spec verify_read(module(), term()) :: verified()
  def verify_read(repo, value) do
    with {:ok, ids} <- collect(value) do
      verify_read_ids(repo, Enum.uniq(ids))
    end
  end

  @spec verify_read_ids(module(), [term()]) :: verified()
  defp verify_read_ids(repo, ids) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case Artifacts.fetch(repo, id) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @spec collect(term()) :: collected()
  defp collect(map) when is_map(map) do
    Enum.reduce_while(map, {:ok, []}, fn {key, value}, {:ok, acc} ->
      case field(key, value) do
        {:ok, ids} -> {:cont, {:ok, ids ++ acc}}
        error -> {:halt, error}
      end
    end)
  end

  defp collect(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acc} ->
      case collect(value) do
        {:ok, ids} -> {:cont, {:ok, ids ++ acc}}
        error -> {:halt, error}
      end
    end)
  end

  defp collect(_), do: {:ok, []}
  @spec field(term(), term()) :: collected()
  defp field("artifact_id", value), do: {:ok, [value]}

  defp field(key, value) when key in ~w(artifact_ids artifact_refs) and is_list(value),
    do: {:ok, value}

  defp field(key, _) when key in ~w(artifact_ids artifact_refs), do: {:error, :invalid_data}
  defp field(_, value), do: collect(value)
end
