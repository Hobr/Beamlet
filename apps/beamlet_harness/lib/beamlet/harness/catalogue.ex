defmodule Beamlet.Harness.Catalogue do
  @moduledoc """
  只保存数据的工具目录；整批成功才返回可调度调用，不调用工具、不解析本地模块。调用方必须在任何派发前完成 batch/2。

  Data-only catalogue and atomic whole-batch validation. No invocation occurs here.
  """
  alias Beamlet.Harness.Arguments

  @typedoc """
  只含名称、说明和 schema 的数据描述，不能包含设置或认证。

  Descriptors keyed by validated Tool name; descriptor string keys and schema relations are runtime checked.
  """
  @type descriptor :: Beamlet.Harness.Model.json_object()
  @typedoc """
  以经过校验的工具名称索引描述；不包含可执行模块。
  """
  @type t :: %{optional(String.t()) => descriptor()}
  @typep batch_result :: {:ok, [Beamlet.Harness.Model.call()]} | {:error, :invalid_tool_batch}

  @doc """
  从最多 64 个不重复描述构造目录。描述仅含 name/description/parameters，说明最多 4096 字节、完整 JSON 最多 16384 字节；错误为 invalid_catalogue。
  """
  @spec new(term()) :: {:ok, t()} | {:error, :invalid_catalogue}
  def new(descriptors) when is_list(descriptors) and length(descriptors) <= 64 do
    if Enum.all?(descriptors, &descriptor?/1) and
         length(Enum.uniq_by(descriptors, & &1["name"])) == length(descriptors),
       do: {:ok, Map.new(descriptors, &{&1["name"], &1})},
       else: {:error, :invalid_catalogue}
  end

  def new(_), do: {:error, :invalid_catalogue}

  @doc """
  重新构造目录并比对键名，拒绝键与描述 name 不一致。
  """
  @spec validate(term()) :: :ok | {:error, :invalid_catalogue}
  def validate(catalogue) when is_map(catalogue) do
    case new(Map.values(catalogue)) do
      {:ok, ^catalogue} -> :ok
      _ -> {:error, :invalid_catalogue}
    end
  end

  def validate(_), do: {:error, :invalid_catalogue}

  @spec descriptor?(term()) :: boolean()
  defp descriptor?(%{"name" => n, "description" => d, "parameters" => s} = descriptor) do
    Map.keys(descriptor) -- ~w(name description parameters) == [] and name?(n) and
      is_binary(d) and String.valid?(d) and byte_size(d) <= 4096 and Arguments.schema?(s) and
      byte_size(Jason.encode!(descriptor)) <= 16_384
  end

  defp descriptor?(_), do: false

  @doc """
  检查便携名称是否为 1..64 个 ASCII 字母、数字、下划线或连字符。
  """
  @spec name?(term()) :: boolean()
  def name?(n), do: is_binary(n) and Regex.match?(~r/\A[a-zA-Z0-9_-]{1,64}\z/, n)

  @doc """
  验证 1..8 个字符串键调用，保留原始顺序及 ID，返回原子键原生调用。ID 必须唯一且为 1..128 字节 UTF-8；每份已解码参数 JSON 最多 16384 字节。任一失败返回 invalid_tool_batch，不返回部分成功。
  """
  @spec batch(term(), term()) :: batch_result()
  def batch(calls, catalogue) when is_list(calls) and length(calls) in 1..8 do
    case validate(catalogue) do
      :ok -> validate_batch(calls, catalogue)
      _ -> {:error, :invalid_tool_batch}
    end
  end

  def batch(_, _), do: {:error, :invalid_tool_batch}

  @spec validate_batch([term()], t()) :: batch_result()
  defp validate_batch(calls, catalogue) do
    Enum.reduce_while(calls, {:ok, [], MapSet.new()}, fn call, {:ok, acc, ids} ->
      with %{"id" => id, "name" => name, "arguments" => args} <- call,
           true <- Map.keys(call) -- ~w(id name arguments) == [],
           true <- is_binary(id) and byte_size(id) in 1..128 and String.valid?(id),
           false <- MapSet.member?(ids, id),
           {:ok, descriptor} <- Map.fetch(catalogue, name),
           :ok <- Arguments.validate(args, descriptor["parameters"]),
           {:ok, encoded} <- Jason.encode(args),
           true <- byte_size(encoded) <= 16_384 do
        {:cont, {:ok, [%{id: id, name: name, arguments: args} | acc], MapSet.put(ids, id)}}
      else
        _ -> {:halt, {:error, :invalid_tool_batch}}
      end
    end)
    |> case do
      {:ok, acc, _} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end
end
