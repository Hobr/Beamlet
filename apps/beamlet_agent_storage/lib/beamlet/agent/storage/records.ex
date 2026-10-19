defmodule Beamlet.Agent.Storage.Records do
  @moduledoc """
  领域记录门面的事务及校验辅助。原子键属性与字符串键持久化数据分开处理；事务负责整组回滚，未知写入结果须凭稳定身份核对，不自动重试。纯转换与校验工具不代替领域所有权和引用检查。

  Shared boundary for the record transaction facades. Validation and comparison
  helpers are pure; transaction helpers run inside the caller's already-open
  transaction. Every facade revalidates identity, stored owner and CAS inputs
  instead of trusting an upstream caller. Errors stay plain atoms from the
  stage-A taxonomy; SQL, connection and configuration detail never escape.
  """
  @typedoc "领域安全错误标签；未知写入结果须核对稳定身份，不包含驱动详情。"
  @type error ::
          :invalid_data
          | :limit
          | :conflict
          | :stale_generation
          | :schema_unsupported
          | :artifact_missing
          | :storage_unavailable
          | :storage_outcome_unknown
          | :unresolved_execution
          | :unsafe_checkpoint
          | :source_not_frozen
          | :invalid_reference
          | :transaction_required
          | :stale_epoch
  @typedoc "领域门面的成功值或安全错误，不授权错误后的自动业务重试。"
  @type result(value) :: {:ok, value} | {:error, error()}
  @typedoc "解码 JSON 值；字符串键及引用关系仍由运行时校验。

Decoded JSON facts; string keys, event variants and reference relations are runtime validated."
  @type value :: Beamlet.Actions.Storage.Records.value()
  @typedoc "字符串键 JSON 对象，可为空；字段间约束由所属门面校验。"
  @type object :: Beamlet.Actions.Storage.Records.object()
  @spec transact(module(), (-> {:ok, value} | {:error, atom()} | nil)) :: result(value)
        when value: var
  @spec settle(module(), (-> {:ok, value} | {:error, atom()} | nil)) :: value when value: var
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
  @spec event_type(term()) :: {:ok, String.t()} | {:error, :schema_unsupported}
  @spec get(module(), module(), term()) :: {:ok, struct()} | {:error, :conflict}
  @spec insert(module(), Ecto.Changeset.t(record)) ::
          {:ok, record} | {:error, :invalid_data | :limit | :conflict}
        when record: var
  @spec changeset_error(Ecto.Changeset.t()) :: :invalid_data | :limit | :conflict
  @spec cas_agent(
          module(),
          Beamlet.Agent.Storage.Schema.Agent.t(),
          non_neg_integer(),
          non_neg_integer(),
          keyword()
        ) :: result(non_neg_integer())
  @spec event_changeset(map()) :: Ecto.Changeset.t(Beamlet.Agent.Storage.Schema.Event.t())
  @spec command_changeset(map()) :: Ecto.Changeset.t(Beamlet.Agent.Storage.Schema.Command.t())
  @spec event_input(term()) ::
          result(%{
            id: String.t(),
            type: String.t(),
            payload: value(),
            causation_id: String.t() | nil
          })
  @spec command_lookup(module(), String.t(), String.t()) ::
          Beamlet.Agent.Storage.Schema.Command.t() | nil
  # This structural conversion preserves arbitrary leaves, unlike the JSON validator.
  @spec plain(term()) :: term()
  @spec plain_key(key) :: key | String.t() when key: var

  alias Beamlet.Agent.Storage.Read
  alias Beamlet.Storage.Transaction
  import Ecto.Query
  alias Beamlet.Agent.Storage.Codec
  alias Beamlet.Agent.Storage.Events
  alias Beamlet.Agent.Storage.Schema.Agent
  alias Beamlet.Agent.Storage.Schema.Command
  alias Beamlet.Agent.Storage.Schema.Event

  @errors ~w(invalid_data limit conflict stale_generation schema_unsupported artifact_missing storage_unavailable storage_outcome_unknown unresolved_execution unsafe_checkpoint source_not_frozen)a
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
    Ecto.ConstraintError ->
      {:error, :conflict}

    Ecto.Query.CastError ->
      {:error, :invalid_data}

    Ecto.ChangeError ->
      {:error, :invalid_data}

    error in ArgumentError ->
      Read.read(fn -> reraise(error, __STACKTRACE__) end)
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

  @doc "核对 Agent schema_version=1 的事件词汇，未知类型返回 schema_unsupported。"
  def event_type(value) do
    if Events.supported?(value, 1), do: {:ok, value}, else: {:error, :schema_unsupported}
  end

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

  @doc "先拒绝旧 generation，再以 lock_version CAS 更新 Agent，成功版本加一；调用方拥有事务。

Generation is checked first: a stale instance must not learn loop by loop that its version moved."
  def cas_agent(repo, agent, expected_version, expected_generation, updates) do
    if agent.generation != expected_generation do
      {:error, :stale_generation}
    else
      query =
        from(a in Agent,
          where:
            a.id == ^agent.id and a.generation == ^expected_generation and
              a.lock_version == ^expected_version,
          update: [set: ^Keyword.put(updates, :lock_version, expected_version + 1)]
        )

      case repo.update_all(query, [], log: false) do
        {1, _} -> {:ok, expected_version + 1}
        {0, _} -> {:error, :conflict}
      end
    end
  end

  @doc "构造 Agent 事件 changeset，检查词汇版本并登记 scope/dedupe 唯一约束。"
  def event_changeset(attrs) do
    changeset = Event.changeset(%Event{}, attrs)

    changeset =
      if Events.supported?(attrs[:type], attrs[:schema_version]),
        do: changeset,
        else: Ecto.Changeset.add_error(changeset, :schema_version, "invalid_data")

    changeset
    |> Ecto.Changeset.unique_constraint([:scope_id, :dedupe_key],
      name: :agent_events_scope_id_dedupe_key_index
    )
  end

  @doc "构造命令响应 changeset 并登记 scope/command_id 唯一约束。"
  def command_changeset(attrs) do
    Command.changeset(%Command{}, attrs)
    |> Ecto.Changeset.unique_constraint([:scope_id, :command_id],
      name: :commands_scope_id_command_id_index
    )
  end

  @doc "规范化调用方提供的 id/type/payload/可选 causation_id；scope、seq 和去重键由门面分配。

Normalizes one caller-supplied history event; scope, seq and dedupe are facade-owned."
  def event_input(event) do
    with {:ok, _} <- fields(event, [:id, :type, :payload], [:causation_id]),
         {:ok, id} <- uuid(event[:id]),
         {:ok, type} <- event_type(event[:type]),
         {:ok, payload} <- json(event[:payload], :event),
         {:ok, causation} <- optional_uuid(event[:causation_id]) do
      {:ok, %{id: id, type: type, payload: payload, causation_id: causation}}
    end
  end

  @doc "在已管理的读写边界内按 scope/command_id 取原始命令行，缺失返回 nil。"
  def command_lookup(repo, scope_id, command_id) do
    query =
      from(c in Command, where: c.scope_id == ^scope_id and c.command_id == ^command_id)

    repo.one(query, log: false)
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
