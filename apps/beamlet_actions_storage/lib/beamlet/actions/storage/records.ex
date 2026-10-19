defmodule Beamlet.Actions.Storage.Records do
  @moduledoc """
  领域记录门面的事务及校验辅助。原子键属性与字符串键持久化数据分开处理；事务负责整组回滚，未知写入结果须凭稳定身份核对，不自动重试。纯转换与校验工具不代替领域所有权和引用检查。

  Shared boundary for the record transaction facades. Validation and comparison
  helpers are pure; transaction helpers run inside the caller's already-open
  transaction. Every facade revalidates identity, stored identity and CAS inputs
  instead of trusting an upstream caller. Errors stay plain atoms from the
  stage-A taxonomy; SQL, connection and configuration detail never escape.
  """
  @typedoc "领域安全错误标签；未知写入结果须核对稳定身份，不包含驱动详情。

Safe facade failures; transactions never expose driver detail."
  @type error ::
          :invalid_data
          | :limit
          | :conflict
          | :stale_epoch
          | :schema_unsupported
          | :artifact_missing
          | :storage_unavailable
          | :storage_outcome_unknown
          | :transaction_required
          | :invalid_reference
  @typedoc "领域门面的成功值或安全错误，不授权错误后的自动业务重试。"
  @type result(value) :: {:ok, value} | {:error, error()}
  @typedoc "解码 JSON 值；字符串键及引用关系仍由运行时校验。

Decoded persisted JSON; key relationships, UUIDs and bounds are runtime validated."
  @type value :: nil | boolean() | number() | String.t() | [value()] | object()
  @typedoc "字符串键 JSON 对象，可为空；字段间约束由所属门面校验。"
  @type object :: %{optional(String.t()) => value()}
  @spec transact(module(), (-> {:ok, value} | {:error, atom()})) :: result(value) when value: var
  @spec settle(module(), (-> {:ok, value} | {:error, atom()})) :: value when value: var
  @spec fields(term(), [atom()], [atom()]) ::
          {:ok, %{optional(atom()) => term()}} | {:error, :invalid_data}
  @spec uuid(term()) :: {:ok, String.t()} | {:error, :invalid_data}
  @spec optional_uuid(term()) :: {:ok, String.t() | nil} | {:error, :invalid_data}
  @spec text(term(), pos_integer()) :: {:ok, String.t()} | {:error, :invalid_data}
  @spec optional_text(term(), pos_integer()) :: {:ok, String.t() | nil} | {:error, :invalid_data}
  @spec count(term()) :: {:ok, non_neg_integer()} | {:error, :invalid_data}
  @spec digest(term()) :: {:ok, String.t()} | {:error, :invalid_data}
  @spec json(term(), atom()) :: {:ok, value()} | {:error, :invalid_data | :limit}
  @spec enum(term(), [String.t()]) :: {:ok, String.t()} | {:error, :invalid_data}
  @spec get(module(), module(), term()) :: {:ok, struct()} | {:error, :conflict}
  @spec insert(module(), Ecto.Changeset.t(record)) ::
          {:ok, record} | {:error, :invalid_data | :limit | :conflict}
        when record: var
  @spec changeset_error(Ecto.Changeset.t()) :: :invalid_data | :limit | :conflict
  # Generic conversion deliberately preserves scalar leaves, including non-JSON input.
  @spec plain(term()) :: term()
  @spec plain_key(key) :: key | String.t() when key: var

  alias Beamlet.Actions.Storage.Codec
  alias Beamlet.Actions.Storage.Read
  alias Beamlet.Storage.Transaction

  @errors ~w(invalid_data limit conflict stale_epoch schema_unsupported artifact_missing storage_unavailable storage_outcome_unknown)a
  @digest ~r/\A[0-9a-f]{64}\z/

  @doc "拥有一次写事务：参与者返回错误即回滚整组写入；无法分类的写入失败返回 storage_outcome_unknown。只窄化识别严格 JSON 加载错误，不掩盖其他程序异常。

Runs one write transaction; rollback keeps the whole write set out of the dataset."
  def transact(repo, fun) do
    case Transaction.write(repo, fn -> settle(repo, fun) end) do
      {:ok, response} -> {:ok, response}
      {:error, reason} when reason in @errors -> {:error, reason}
      {:error, _} -> {:error, :storage_outcome_unknown}
    end
  rescue
    Ecto.ConstraintError -> {:error, :conflict}
    Ecto.Query.CastError -> {:error, :invalid_data}
    Ecto.ChangeError -> {:error, :invalid_data}
    error in ArgumentError -> Read.read(fn -> reraise(error, __STACKTRACE__) end)
  end

  defp settle(repo, fun) do
    case fun.() do
      {:ok, response} -> response
      {:error, reason} when is_atom(reason) -> repo.rollback(reason)
      _ -> repo.rollback(:storage_outcome_unknown)
    end
  end

  @doc "只接受非结构体的原子键 map，检查必填键并拒绝未知键。"
  def fields(attrs, required, optional) do
    keys = if is_map(attrs) and not is_struct(attrs), do: Map.keys(attrs)

    cond do
      is_nil(keys) -> {:error, :invalid_data}
      not Enum.all?(keys, &is_atom/1) -> {:error, :invalid_data}
      not Enum.all?(required, &Map.has_key?(attrs, &1)) -> {:error, :invalid_data}
      not Enum.all?(keys, &(&1 in required or &1 in optional)) -> {:error, :invalid_data}
      true -> {:ok, attrs}
    end
  end

  @doc "校验规范 UUID，成功返回原字符串，失败返回 invalid_data。"
  def uuid(value) do
    if Codec.uuid?(value), do: {:ok, value}, else: {:error, :invalid_data}
  end

  @doc "允许 nil，否则按规范 UUID 校验。"
  def optional_uuid(nil), do: {:ok, nil}
  def optional_uuid(value), do: uuid(value)

  @doc "校验非空 UTF-8 字符串及最大字节数，失败返回 invalid_data。"
  def text(value, max) when is_binary(value) do
    if String.valid?(value) and byte_size(value) in 1..max,
      do: {:ok, value},
      else: {:error, :invalid_data}
  end

  def text(_, _), do: {:error, :invalid_data}

  @doc "允许 nil，否则校验非空 UTF-8 文本及最大字节数。"
  def optional_text(nil, _), do: {:ok, nil}
  def optional_text(value, max), do: text(value, max)

  @doc "只接受非负整数，失败返回 invalid_data。"
  def count(value) when is_integer(value) and value >= 0, do: {:ok, value}
  def count(_), do: {:error, :invalid_data}

  @doc "检查 64 位小写十六进制摘要字符串；不是计算摘要。"
  def digest(value) when is_binary(value) do
    if Regex.match?(@digest, value), do: {:ok, value}, else: {:error, :invalid_data}
  end

  def digest(_), do: {:error, :invalid_data}

  @doc "按领域预算验证 JSON 并返回原值；不负责业务引用关系校验。"
  def json(value, kind) do
    case Codec.encode(value, kind) do
      {:ok, _bytes} -> {:ok, value}
      {:error, reason} when reason in [:limit, :invalid_data] -> {:error, reason}
      _ -> {:error, :invalid_data}
    end
  end

  @doc "将非 nil 原子转换为字符串，并核对允许值列表；失败返回 invalid_data。"
  def enum(value, allowed) when is_atom(value) and not is_nil(value),
    do: enum(Atom.to_string(value), allowed)

  def enum(value, allowed) when is_binary(value) do
    if value in allowed, do: {:ok, value}, else: {:error, :invalid_data}
  end

  def enum(_, _), do: {:error, :invalid_data}

  @doc "按主键读取 schema，缺失返回 conflict；须由领域读写边界包裹数据库错误。"
  def get(repo, schema, id) do
    case repo.get(schema, id, log: false) do
      nil -> {:error, :conflict}
      record -> {:ok, record}
    end
  end

  @doc "插入 changeset，将验证/唯一性错误映射为领域错误；不拥有外层提交。"
  def insert(repo, changeset) do
    case repo.insert(changeset, log: false) do
      {:ok, record} -> {:ok, record}
      {:error, changeset} -> {:error, changeset_error(changeset)}
    end
  end

  @doc "依次将大小、唯一性及其他 changeset 错误归为 limit/conflict/invalid_data。"
  def changeset_error(changeset) do
    errors =
      Enum.map(changeset.errors, fn {_field, {message, opts}} ->
        {message, Keyword.get(opts, :constraint)}
      end)

    cond do
      Enum.any?(errors, &(elem(&1, 0) == "limit")) -> :limit
      Enum.any?(errors, &(elem(&1, 1) == :unique)) -> :conflict
      true -> :invalid_data
    end
  end

  @doc "将结构体及 map 转成普通数据，去除 Ecto 元数据，原子键变字符串，时间变 ISO 8601；任意标量叶原样保留，因此不是 JSON 验证器。

Plain, atom-free data: timestamps become ISO 8601 strings and struct meta is dropped."
  def plain(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def plain(nil), do: nil

  def plain(%_{} = struct) do
    struct |> Map.from_struct() |> Map.delete(:__meta__) |> plain()
  end

  def plain(%{} = map) do
    Map.new(map, fn {key, value} -> {plain_key(key), plain(value)} end)
  end

  def plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  def plain(value), do: value

  defp plain_key(key) when is_atom(key), do: Atom.to_string(key)
  defp plain_key(key), do: key
end
