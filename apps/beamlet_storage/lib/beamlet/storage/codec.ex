defmodule Beamlet.Storage.Codec do
  @moduledoc """
  与领域大小策略无关的严格持久化 JSON 编解码。默认上限 4MiB，可传正整数字节上限；深度上限 32、节点预算 100000。对象键按序输出，整数与浮点拼写保留。拒绝重复键、无效 UTF-8、结构体、进程等运行时值及结构化凭据字段；普通字符串内容仍由调用方审查。

  Strict persisted JSON, independent of Erlang wire limits. Strings are not
  secret-scanned: callers must enforce their content policy. Structured credential
  fields are rejected recursively. Numbers retain integer versus float spelling.
  """
  @depth 32
  @nodes 100_000
  @secret_keys ~w(credentials credential api_key apikey token access_token refresh_token password secret authorization private_key)
  # A heuristic, not a secret scanner: exact credential names plus underscore- or
  # dash-separated credential segments (client_secret, bearer_token, api-key).
  # Reference-shaped keys (secret_ref, credential_id, api_key_name) are legitimate
  # because persisted definitions point at secrets instead of holding them, and the
  # plural "tokens" is absent so counters such as max_tokens remain storable.
  @secret_segments ~w(credential credentials password passwd secret secrets token)
  @reference_suffixes ~w(ref refs id ids name names path)

  @typedoc "可持久化 JSON 值；字符串键、凭据策略及资源预算由运行时校验。

Persistable JSON. Exact string keys, credential policy and resource bounds require runtime validation."
  @type value :: nil | boolean() | number() | String.t() | [value()] | object()
  @typedoc "仅允许 UTF-8 字符串键的 JSON 对象，可为空；运行时继续拒绝凭据字段。"
  @type object :: %{optional(String.t()) => value()}
  @typedoc "invalid_data 表示内容/形状不合法，limit 表示超出资源预算。"
  @type error :: :invalid_data | :limit
  @typep budget :: {integer(), integer()}
  @typep walk_result :: {:ok, budget()} | {:error, error()}
  @doc "原样返回正整数字节预算；调用方必须提供正整数，其他输入不在此函数契约内。"
  @spec limit(pos_integer()) :: pos_integer()
  def limit(bytes) when is_integer(bytes) and bytes > 0, do: bytes

  @doc "校验并输出键排序的 UTF-8 JSON；无效输入返回 invalid_data，超过字节/深度/节点预算返回 limit。

Validates and emits sorted-key UTF-8 JSON, never ETF or inspected terms."
  @spec encode(term(), pos_integer()) :: {:ok, binary()} | {:error, error()}
  def encode(value, kind \\ 4_194_304) do
    with {:ok, _} <- walk(value, 0, {@nodes, limit(kind)}),
         encoded <- value |> canonical() |> IO.iodata_to_binary(),
         true <- byte_size(encoded) <= limit(kind) do
      {:ok, encoded}
    else
      false -> {:error, :limit}
      {:error, _} = error -> error
    end
  end

  @doc "在解析前限制字节和嵌套深度，拒绝重复对象键，再执行与 encode 相同的内容/预算校验；返回解码值或 invalid_data/limit。"
  @spec decode(term(), pos_integer()) :: {:ok, value()} | {:error, error()}
  def decode(bytes, kind \\ 4_194_304)

  def decode(bytes, kind) when is_binary(bytes) do
    if byte_size(bytes) <= limit(kind) do
      with :ok <- scan_depth(bytes, 0, false, false),
           {:ok, value} <- Jason.decode(bytes, objects: :ordered_objects),
           {:ok, value} <- plain_objects(value),
           {:ok, _} <- encode(value, kind) do
        {:ok, value}
      else
        {:error, reason} when reason in [:limit, :invalid_data] -> {:error, reason}
        _ -> {:error, :invalid_data}
      end
    else
      {:error, :limit}
    end
  end

  def decode(_, _), do: {:error, :invalid_data}

  @doc "对规范 JSON 字节计算小写 SHA-256；先执行 encode 的全部校验。"
  @spec digest(term(), pos_integer()) :: {:ok, String.t()} | {:error, error()}
  def digest(value, kind \\ 4_194_304) do
    with {:ok, bytes} <- encode(value, kind), do: {:ok, hash(bytes)}
  end

  @doc "对原始 iodata 计算小写 SHA-256 十六进制摘要；不执行 JSON 校验。"
  @spec hash(iodata()) :: String.t()
  def hash(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  @doc "判断输入是否已经是 Ecto.UUID.cast 接受的规范 UUID 字符串；不进行转换。"
  @spec uuid?(term()) :: boolean()
  def uuid?(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, ^value} -> true
      _ -> false
    end
  end

  def uuid?(_), do: false

  # Byte accounting happens during traversal, before constructing a whole JSON value.
  @spec walk(term(), non_neg_integer(), budget()) :: walk_result()
  defp walk(_, depth, {nodes, bytes}) when depth > @depth or nodes <= 0 or bytes < 0,
    do: {:error, :limit}

  defp walk(value, _, budget) when is_boolean(value) or is_nil(value) or is_integer(value),
    do: spend(budget, byte_size(Jason.encode!(value)))

  defp walk(value, _, budget) when is_float(value) do
    # BEAM floats cannot represent NaN/infinity; malformed JSON numbers are
    # rejected by Jason before reaching this clause.
    spend(budget, byte_size(Jason.encode!(value)))
  end

  defp walk(value, _, {_, bytes} = budget) when is_binary(value) do
    cond do
      byte_size(value) > bytes -> {:error, :limit}
      not String.valid?(value) -> {:error, :invalid_data}
      true -> spend(budget, byte_size(Jason.encode!(value)))
    end
  end

  defp walk(value, depth, budget) when is_list(value) do
    with {:ok, left} <- spend(budget, 2), do: walk_list(value, depth, left, false)
  end

  defp walk(%{__struct__: _}, _, _), do: {:error, :invalid_data}

  defp walk(value, depth, budget) when is_map(value) do
    with {:ok, left} <- spend(budget, if(map_size(value) == 0, do: 2, else: 1)) do
      Enum.reduce_while(value, {:ok, left}, &walk_pair(&1, &2, depth))
    end
  end

  defp walk(_, _, _), do: {:error, :invalid_data}

  @spec walk_pair({term(), term()}, {:ok, budget()}, non_neg_integer()) ::
          {:cont, walk_result()} | {:halt, walk_result()}
  defp walk_pair({key, item}, {:ok, remaining}, depth) do
    if is_binary(key) and byte_size(key) <= elem(remaining, 1) and
         not credential_key?(key) do
      with {:ok, left} <- walk(key, depth + 1, remaining),
           {:ok, left} <- spend_bytes(left, 2),
           {:ok, left} <- walk(item, depth + 1, left) do
        {:cont, {:ok, left}}
      else
        error -> {:halt, error}
      end
    else
      {:halt, {:error, :invalid_data}}
    end
  end

  @spec credential_key?(binary()) :: boolean()
  defp credential_key?(key) do
    normalized = key |> String.downcase() |> String.replace("-", "_")
    segments = String.split(normalized, "_", trim: true)

    cond do
      normalized in @secret_keys -> true
      segments == [] -> false
      List.last(segments) in @reference_suffixes -> false
      true -> Enum.any?(segments, &(&1 in @secret_segments))
    end
  end

  @spec spend(budget(), non_neg_integer()) :: walk_result()
  defp spend({nodes, bytes}, used) when bytes >= used and nodes > 0,
    do: {:ok, {nodes - 1, bytes - used}}

  defp spend(_, _), do: {:error, :limit}
  @spec spend_bytes(budget(), non_neg_integer()) :: walk_result()
  defp spend_bytes({nodes, bytes}, used) when bytes >= used, do: {:ok, {nodes, bytes - used}}
  defp spend_bytes(_, _), do: {:error, :limit}
  @spec walk_list(term(), non_neg_integer(), budget(), boolean()) :: walk_result()
  defp walk_list([], _, budget, _), do: {:ok, budget}

  defp walk_list([head | tail], depth, budget, comma?) do
    with {:ok, left} <- spend_bytes(budget, if(comma?, do: 1, else: 0)),
         {:ok, left} <- walk(head, depth + 1, left),
         do: walk_list(tail, depth, left, true)
  end

  defp walk_list(_, _, _, _), do: {:error, :invalid_data}

  # 解析前先限制递归，避免解码树分配后才发现深度超限。
  # Bound parser recursion before Jason allocates a decoded tree.
  @spec scan_depth(binary(), integer(), boolean(), boolean()) :: :ok | {:error, :limit}
  defp scan_depth(_, depth, _, _) when depth > @depth + 1, do: {:error, :limit}
  defp scan_depth(<<>>, _, _, _), do: :ok

  defp scan_depth(<<_, rest::binary>>, depth, true, true),
    do: scan_depth(rest, depth, true, false)

  defp scan_depth(<<92, rest::binary>>, depth, true, false),
    do: scan_depth(rest, depth, true, true)

  defp scan_depth(<<34, rest::binary>>, depth, quoted, false),
    do: scan_depth(rest, depth, not quoted, false)

  defp scan_depth(<<c, rest::binary>>, depth, false, _) when c in [123, 91],
    do: scan_depth(rest, depth + 1, false, false)

  defp scan_depth(<<c, rest::binary>>, depth, false, _) when c in [125, 93],
    do: scan_depth(rest, depth - 1, false, false)

  defp scan_depth(<<_, rest::binary>>, depth, quoted, escaped),
    do: scan_depth(rest, depth, quoted, escaped)

  # Reject duplicate keys rather than silently accepting Jason's last value.
  @spec plain_objects(term()) :: {:ok, value()} | {:error, :invalid_data}
  defp plain_objects(%Jason.OrderedObject{values: pairs}) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with false <- Map.has_key?(acc, key), {:ok, value} <- plain_objects(value) do
        {:cont, {:ok, Map.put(acc, key, value)}}
      else
        _ -> {:halt, {:error, :invalid_data}}
      end
    end)
  end

  defp plain_objects(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case plain_objects(value) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp plain_objects(value), do: {:ok, value}

  @spec canonical(value()) :: iodata()
  defp canonical(value) when is_map(value) do
    pairs =
      value
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, item} -> [Jason.encode!(key), ":", canonical(item)] end)

    ["{", Enum.intersperse(pairs, ","), "}"]
  end

  defp canonical(value) when is_list(value),
    do: ["[", Enum.intersperse(Enum.map(value, &canonical/1), ","), "]"]

  defp canonical(value), do: Jason.encode!(value)
end
