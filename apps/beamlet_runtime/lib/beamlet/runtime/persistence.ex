defmodule Beamlet.Runtime.Persistence do
  @moduledoc """
  可选持久化接线：authority 先准备并声明发送，执行器先记录 start_intent，authority 接受唯一 Result 后才通知 sink。通过 Runtime 的 child spec 显式启动监督树；本模块不启动 Repo。未决执行和未知提交均不授权再次发送，消费结果由调用方编排。

  Explicit opt-in durable wiring for the normal Runtime path.

  Supplying this struct to the `Beamlet.Runtime` child spec / `submit/2` makes the
  authority commit an Operation with one prepared attempt before dispatch, the
  executor journal its own start intent before starting a worker, and the
  coordinator accept exactly one authority Result before notifying a sink.
  Without it Runtime stays ephemeral. The struct carries only opaque Repo handles
  and stable identities; PIDs, references, monitors, timers and worker handles
  stay in memory.

  Work may be prepared atomically by a caller-owned transaction. Runtime
  accepts its committed identity through `submit/2`'s `prepared:` option; Result
  acceptance belongs only to the Operation and does not advance caller orchestration state.
  """
  alias Beamlet.Actions.{Operation, Result}
  alias Beamlet.Actions.Storage.{Codec, DispatchScopes, OperationRecords}
  alias Beamlet.Storage.Admission

  @enforce_keys [:authority_repo, :journal_repo, :authority_id, :executor_id, :executor_boot_id]
  defstruct [
    :authority_repo,
    :journal_repo,
    :authority_id,
    :executor_id,
    :executor_boot_id,
    :dispatch_scope_id,
    :dispatch_epoch
  ]

  @typedoc """
  持久化 Repo 句柄及稳定 UUID 接线；scope/epoch 必须同时给出或同时为空。

  Durable wiring. Repo handles are trusted Ecto repository identities, checked by the storage facade.
  """
  @type t :: %__MODULE__{
          authority_repo: term(),
          journal_repo: term(),
          authority_id: binary(),
          executor_id: binary(),
          executor_boot_id: binary(),
          dispatch_scope_id: binary() | nil,
          dispatch_epoch: non_neg_integer() | nil
        }

  @typedoc """
  字符串键已提交 JSON；UUID 拼写、枚举、深度与字节数由 codec 验证。

  String-key committed storage payload. Literal string keys, UUID spelling,
  string enums, depth and byte limits remain runtime codec constraints.
  """
  @type object :: Beamlet.Actions.json_object()
  @typedoc """
  已提交 Operation/attempt 的 ID、摘要、两个版本及 scope/epoch，不能替换尝试。

  Committed identity with operation_id, attempt_id, description_digest,
  attempt_version and lock_version; optional paired dispatch_scope_id/dispatch_epoch.
  This is a storage representation, not an atom-key admission envelope.
  """
  @type prepared :: object()
  @typedoc """
  尚未通过 durable codec 的字符串键候选，转换器保留开放输入域。

  Candidate string-key payload before the durable codec checks JSON safety.
  Operation payload, metadata, environment and handler Result data retain their
  open input domain; description/1 and result_payload/1 do not validate them.
  """
  @type candidate :: %{optional(binary()) => term()}
  @typedoc "带稳定 ID、内容摘要及终态观察的执行器回执。"
  @type receipt :: %{id: binary(), digest: binary(), content: object()}
  @typedoc "执行器当前尝试身份、描述摘要、CAS 版本与固定回执 ID。"
  @type journal :: %{
          authority_id: binary(),
          operation_id: binary(),
          attempt_id: binary(),
          description_digest: binary(),
          executor_id: binary(),
          executor_boot_id: binary(),
          lock_version: non_neg_integer(),
          receipt_id: binary()
        }
  @typep prepare_result :: {:ok, prepared() | nil} | {:error, :invalid_operation | :unavailable}
  @spec new(nil | t() | keyword()) :: nil | t()
  @spec uuid() :: binary()
  @spec description(Operation.t()) :: candidate()
  @spec prepare(t() | nil, Operation.t()) :: prepare_result()
  @spec admission_failure(term()) :: :ok
  @spec receipt(journal(), Result.t(), object()) ::
          {:ok, receipt()} | {:error, :durable_unavailable}
  @spec evidence(receipt()) :: object()
  @spec result_payload(Result.t()) :: candidate()
  # This converter deliberately passes unsupported values through to the codec;
  # it is not a validator and may return the same live value supplied by a caller.
  @spec value(term()) :: term()
  @spec submit_error(term()) :: :invalid_operation | :unavailable
  @spec validate!(t()) :: t()
  @spec scope?(t()) :: boolean()

  @doc "标准化显式接线；nil 保持内存模式，无效 UUID 或 scope/epoch 配对抛 ArgumentError，不打开 Repo。"
  def new(nil), do: nil
  def new(%__MODULE__{} = persistence), do: validate!(persistence)

  def new(opts) when is_list(opts) do
    allowed =
      ~w(authority_repo journal_repo authority_id executor_id executor_boot_id dispatch_scope_id dispatch_epoch)a

    unless Keyword.keyword?(opts) and Enum.all?(Keyword.keys(opts), &(&1 in allowed)),
      do: raise(ArgumentError, "invalid persistence configuration")

    validate!(%__MODULE__{
      authority_repo: opts[:authority_repo],
      journal_repo: opts[:journal_repo],
      authority_id: opts[:authority_id],
      executor_id: opts[:executor_id],
      executor_boot_id: opts[:executor_boot_id],
      dispatch_scope_id: opts[:dispatch_scope_id],
      dispatch_epoch: opts[:dispatch_epoch]
    })
  end

  @doc "生成新的持久化 UUID 身份。"
  def uuid, do: Ecto.UUID.generate()

  @doc """
  构造固定逻辑描述，排除瞬态 credentials；转换不代替 codec 验证。

  Fixed logical Operation description, excluding transient invocation credentials.
  """
  def description(%Operation{} = operation) do
    %{
      "kind" => operation.kind,
      "protocol_version" => operation.version,
      "payload" => operation.payload,
      "budget" => %{"budget_ms" => operation.budget_ms},
      "claims" => operation.claims,
      "safety" => %{
        "metadata" => operation.metadata,
        "capabilities" => operation.capabilities,
        "environment" => operation.environment,
        "allowed_nodes" => value(operation.allowed_nodes)
      }
    }
  end

  @doc """
  在 dispatch 前提交不可变 Operation 与一个尝试；nil 接线不写入，存储失败返回安全错误。

  Authority commit of the immutable Operation and one prepared attempt, before dispatch.
  """
  def prepare(nil, _operation), do: {:ok, nil}

  def prepare(%__MODULE__{} = persistence, %Operation{} = operation) do
    attempt_id = uuid()

    attrs = %{
      operation: %{
        id: uuid(),
        description: description(operation),
        dispatch_scope_id: persistence.dispatch_scope_id,
        dispatch_epoch: persistence.dispatch_epoch
      },
      attempt: %{
        attempt_id: attempt_id,
        executor_id: persistence.executor_id,
        executor_boot_id: persistence.executor_boot_id,
        budget: %{"budget_ms" => operation.budget_ms}
      }
    }

    case OperationRecords.prepare(persistence.authority_repo, attrs) do
      {:ok, prepared} ->
        {:ok, prepared}

      {:error, reason} ->
        admission_failure(reason)
        {:error, submit_error(reason)}
    end
  end

  # A failed durable write turns host admission off until a fresh probe succeeds, so
  # a later submit cannot be admitted on a stale "the Repo is registered" belief.
  defp admission_failure(reason) when reason in [:storage_unavailable, :storage_outcome_unknown],
    do: Admission.failure(reason)

  defp admission_failure(_reason), do: :ok

  @doc """
  构建执行器终态证据与稳定回执摘要，非法内容返回 durable_unavailable。

  Executor-local evidence: terminal observation plus stable receipt identity.
  """
  def receipt(journal, %Result{} = result, termination) do
    content = %{
      "version" => 1,
      "authority_id" => journal.authority_id,
      "operation_id" => journal.operation_id,
      "attempt_id" => journal.attempt_id,
      "executor_id" => journal.executor_id,
      "executor_boot_id" => journal.executor_boot_id,
      "description_digest" => journal.description_digest,
      "result" => result_payload(result),
      "termination" => termination
    }

    case Codec.digest(content, :event) do
      {:ok, digest} -> {:ok, %{id: journal.receipt_id, digest: digest, content: content}}
      {:error, _} -> {:error, :durable_unavailable}
    end
  end

  @doc """
  构造 authority 保存的回执证据，包含结果和终止观察。

  Plain receipt evidence for the authority; no structs or live values are persisted.
  """
  def evidence(receipt) do
    %{
      "version" => 1,
      "receipt_id" => receipt.id,
      "receipt_digest" => receipt.digest,
      "result" => receipt.content["result"],
      "termination" => receipt.content["termination"]
    }
  end

  @doc "转换 Result 为字符串键候选数据；最终 JSON 安全性仍由 codec 验证。"
  def result_payload(%Result{} = result) do
    %{
      "operation_id" => result.operation_id,
      "execution_id" => result.execution_id,
      "status" => Atom.to_string(result.status),
      "reason" => value(result.reason),
      "value" => value(result.value),
      "source" => Atom.to_string(result.source),
      "metadata" => Map.new(result.metadata, fn {key, item} -> {to_string(key), value(item)} end)
    }
  end

  @doc false
  # A durable Result is plain JSON data: labels the handler carried as atoms are
  # stored as strings, so a receipt always has a stable digest.
  def value(item) when item in [nil, true, false], do: item
  def value(item) when is_atom(item), do: Atom.to_string(item)
  def value(item) when is_list(item), do: Enum.map(item, &value/1)

  def value(item) when is_map(item) and not is_struct(item) do
    Map.new(item, fn {key, child} -> {value(key), value(child)} end)
  end

  def value(item), do: item

  defp submit_error(:invalid_data), do: :invalid_operation
  defp submit_error(:limit), do: :invalid_operation
  defp submit_error(_reason), do: :unavailable

  defp validate!(%__MODULE__{} = persistence) do
    valid =
      not is_nil(persistence.authority_repo) and not is_nil(persistence.journal_repo) and
        Codec.uuid?(persistence.authority_id) and Codec.uuid?(persistence.executor_id) and
        Codec.uuid?(persistence.executor_boot_id) and scope?(persistence)

    unless valid, do: raise(ArgumentError, "invalid persistence configuration")
    persistence
  end

  defp scope?(persistence) do
    DispatchScopes.validate_binding(
      persistence.dispatch_scope_id,
      persistence.dispatch_epoch
    ) == :ok
  end
end
