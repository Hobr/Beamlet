defmodule Beamlet.Actions do
  @moduledoc """
  生产者与执行器共享的中立数据校验；不执行操作，也不加载适配器。普通数据与专用凭据采用不同策略，类型声明不能代替这些运行时检查。

  Data validation shared by operation producers and executors.
  """
  @forbidden ~w(password secret token credential credentials api_key authorization root workspace_root)a
  @typedoc """
  普通递归数据；元数据也可为标量或列表。敏感键、UTF-8、深度与大小由运行时限定。

  Ordinary bounded data. Secret labels, UTF-8, depth and byte limits remain runtime checks.
  """
  @type data :: atom() | number() | binary() | [data()] | %{optional(data()) => data()}
  @typedoc """
  专用凭据的 JSON 值；任意原子、可执行项和结构体不属于有效输入。

  JSON credential data; UTF-8, root-label, depth and size restrictions are runtime checks.
  """
  @type json_value :: nil | boolean() | number() | String.t() | [json_value()] | json_object()
  @typedoc """
  字符串键 JSON 对象；空对象是有效的默认凭据。
  """
  @type json_object :: %{optional(String.t()) => json_value()}

  @doc """
  检查普通数据的 UTF-8、深度（根为 0，最多 24）及 Erlang 外部序列化字节数。拒绝结构体、进程、引用、函数、元组和预定义敏感键；不作脱敏或内容审计。
  """
  @spec bounded?(term(), term()) :: boolean()
  def bounded?(term, bytes) do
    data?(term, 0) and :erlang.external_size(term) <= bytes
  rescue
    _ -> false
  end

  @doc """
  检查专用字符串键 JSON 对象：最多 32 个顶层键、键名 1..128 字节、深度 24、完整 JSON 最多 16384 字节。递归拒绝大小写不敏感的 root/workspace_root；允许其他凭据标签。

  Validates a dedicated credential JSON object, including its complete JSON byte size.
  """
  @spec credentials?(term()) :: boolean()
  def credentials?(value) do
    is_map(value) and not is_struct(value) and map_size(value) <= 32 and
      Enum.all?(value, fn {key, _} ->
        is_binary(key) and byte_size(key) in 1..128 and String.valid?(key)
      end) and credential_data?(value, 0) and
      IO.iodata_length(:json.encode(value)) <= 16_384
  rescue
    _ -> false
  end

  @spec credential_data?(term(), non_neg_integer()) :: boolean()
  defp credential_data?(_, depth) when depth > 24, do: false
  defp credential_data?(value, _) when is_binary(value), do: String.valid?(value)

  defp credential_data?(value, _) when is_number(value) or value in [true, false, nil],
    do: true

  defp credential_data?([], _), do: true

  defp credential_data?([head | tail], depth),
    do: credential_data?(head, depth + 1) and credential_list?(tail, depth)

  defp credential_data?(value, depth) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, item} ->
      is_binary(key) and String.valid?(key) and
        String.downcase(key) not in ["root", "workspace_root"] and
        credential_data?(key, depth + 1) and credential_data?(item, depth + 1)
    end)
  end

  defp credential_data?(_, _), do: false
  @spec credential_list?(term(), non_neg_integer()) :: boolean()
  defp credential_list?([], _), do: true

  defp credential_list?([head | tail], depth),
    do: credential_data?(head, depth + 1) and credential_list?(tail, depth)

  defp credential_list?(_, _), do: false

  @spec data?(term(), non_neg_integer()) :: boolean()
  defp data?(_, depth) when depth > 24, do: false
  defp data?(x, _) when is_binary(x), do: String.valid?(x)
  defp data?(x, _) when is_number(x) or is_atom(x), do: true
  defp data?(x, depth) when is_list(x), do: Enum.all?(x, &data?(&1, depth + 1))

  defp data?(x, depth) when is_map(x) and not is_struct(x) do
    Enum.all?(x, fn {k, v} ->
      k not in @forbidden and k not in Enum.map(@forbidden, &Atom.to_string/1) and
        data?(k, depth + 1) and data?(v, depth + 1)
    end)
  end

  defp data?(_, _), do: false
end
