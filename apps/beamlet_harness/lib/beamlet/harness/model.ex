defmodule Beamlet.Harness.Model do
  @moduledoc """
  提供者中立的模型行为与校验。请求、回复和历史采用原生数据；配置和凭据显式传入，便携 provider ID 只映射受信的本地注册模块。

  Provider-neutral bounded model contracts and trusted local provider registration.
  """
  alias Beamlet.Harness.{Catalogue, Context}
  @limit 1_048_576
  @typedoc """
  字符串键 JSON 的递归值；字面键、UTF-8、深度和大小仍由运行时检查。

  String-key JSON; exact wire fields and UTF-8/depth/byte limits are validated at runtime.
  """
  @type json_value :: nil | boolean() | number() | String.t() | [json_value()] | json_object()
  @typedoc """
  字符串键 JSON 对象，可为空。
  """
  @type json_object :: %{optional(String.t()) => json_value()}
  @typedoc """
  显式的配置与专用凭据；不从环境变量推断认证。

  Explicit provider invocation, never inferred from ambient credentials.
  """
  @type invocation :: %{config: json_object(), credentials: json_object()}
  @typedoc """
  原生消息与目录组成的请求；精确字段由 validate_request/1 检查。
  """
  @type request :: %{messages: [json_object()], catalogue: Catalogue.t()}
  @typedoc """
  原生调用，arguments 是已解码对象，不是 JSON 字符串。
  """
  @type call :: %{id: String.t(), name: String.t(), arguments: json_object()}
  @typedoc """
  文本回复或有序、非空工具调用批次；最多 8 个调用。

  A text response or an ordered, nonempty Tool batch.
  """
  @type reply ::
          %{kind: :text, content: String.t(), calls: []}
          | %{kind: :tool_calls, content: String.t() | nil, calls: nonempty_list(call())}
  @typedoc """
  受信本地 provider 注册；便携 ID 不直接指定执行代码。
  """
  @type registry :: %{optional(String.t()) => module()}
  @typedoc """
  成功或安全原子错误，不携带供应商原始响应和认证。
  """
  @type validation :: :ok | {:error, atom()}
  @doc "纯校验显式 invocation，叠加通用限制与适配器字段要求；不得联网或解析环境认证。"
  @callback validate_invocation(term()) :: validation()
  @doc "执行一次模型调用并返回中立回复或安全原子错误；直接调用也应校验请求和 invocation，不自动重试。"
  @callback complete(request(), invocation(), Context.t()) :: {:ok, reply()} | {:error, atom()}

  @doc """
  返回内置 deterministic 与 openai-compatible 注册，不发起网络请求。
  """
  @spec default_providers() :: registry()
  def default_providers do
    %{
      "openai-compatible" => Beamlet.Harness.Models.OpenAICompatible,
      "deterministic" => Beamlet.Harness.Models.Deterministic
    }
  end

  @doc """
  检查 provider ID 的便携名称语法，不创建原子或加载模块。
  """
  @spec provider_id?(term()) :: boolean()
  def provider_id?(id), do: Catalogue.name?(id)

  @doc """
  校验最多 32 个 ID 到本地模块的注册；模块必须可加载且导出两个模型回调。不会调用回调验证配置。
  """
  @spec validate_registry(term()) :: :ok | {:error, :invalid_model_providers}
  def validate_registry(registry)
      when is_map(registry) and not is_struct(registry) and map_size(registry) <= 32 do
    if Enum.all?(registry, fn {id, module} ->
         provider_id?(id) and is_atom(module) and Code.ensure_loaded?(module) and
           function_exported?(module, :validate_invocation, 1) and
           function_exported?(module, :complete, 3)
       end), do: :ok, else: {:error, :invalid_model_providers}
  end

  def validate_registry(_), do: {:error, :invalid_model_providers}

  # 明确拒绝原子键，不能依赖编码器自动把它们转换为字符串。
  # JSON validation deliberately does not use Jason's atom-key coercion.
  @doc """
  按给定起始深度检查字符串键 JSON，最大深度 24；拒绝结构体和非 JSON 原子。
  """
  @spec json?(term(), non_neg_integer()) :: boolean()
  def json?(value, depth \\ 0)
  def json?(_, depth) when depth > 24, do: false
  def json?(value, _) when is_binary(value), do: String.valid?(value)
  def json?(value, _) when is_number(value) or is_boolean(value) or is_nil(value), do: true

  def json?(value, depth) when is_list(value) do
    Enum.all?(value, &json?(&1, depth + 1))
  rescue
    _ -> false
  end

  def json?(value, depth) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, child} ->
      is_binary(key) and String.valid?(key) and json?(child, depth + 1)
    end)
  end

  def json?(_, _), do: false

  @doc """
  通用校验：恰好 config/credentials 两个字段，各为最多 16384 字节 JSON 对象。config 递归拒绝敏感/根目录标签；credentials 最多 32 个顶层键，递归拒绝 root/workspace_root。适配器仍需校验自己的必填字段。
  """
  @spec validate_invocation(term()) :: :ok | {:error, :invalid_invocation}
  def validate_invocation(%{config: config, credentials: credentials} = invocation) do
    if map_size(invocation) == 2 and valid_config?(config) and valid_credentials?(credentials),
      do: :ok,
      else: {:error, :invalid_invocation}
  end

  def validate_invocation(_), do: {:error, :invalid_invocation}

  @spec valid_config?(term()) :: boolean()
  defp valid_config?(config),
    do: object?(config) and ordinary?(config) and bounded?(config, 16_384)

  @spec valid_credentials?(term()) :: boolean()
  defp valid_credentials?(credentials),
    do:
      object?(credentials) and map_size(credentials) <= 32 and
        Enum.all?(Map.keys(credentials), &(byte_size(&1) in 1..128)) and
        no_roots?(credentials) and bounded?(credentials, 16_384)

  @spec object?(term()) :: boolean()
  defp object?(value), do: is_map(value) and not is_struct(value) and json?(value)

  @spec ordinary?(json_value()) :: boolean()
  defp ordinary?(value) when is_map(value) do
    Enum.all?(value, fn {k, v} ->
      String.downcase(k) not in ~w(api_key token credential credentials secret password authorization root workspace_root) and
        ordinary?(v)
    end)
  end

  defp ordinary?(value) when is_list(value), do: Enum.all?(value, &ordinary?/1)
  defp ordinary?(_), do: true

  @spec no_roots?(json_value()) :: boolean()
  defp no_roots?(value) when is_map(value),
    do:
      Enum.all?(value, fn {k, v} ->
        String.downcase(k) not in ~w(root workspace_root) and no_roots?(v)
      end)

  defp no_roots?(value) when is_list(value), do: Enum.all?(value, &no_roots?/1)
  defp no_roots?(_), do: true

  @spec bounded?(term(), pos_integer()) :: boolean()
  defp bounded?(value, limit) do
    case Jason.encode(value) do
      {:ok, json} -> byte_size(json) <= limit
      _ -> false
    end
  end

  @doc """
  检查精确的 messages/catalogue 请求、目录与完整有序历史，完整 JSON 最多 1048576 字节。传播目录、上下文或历史错误，超出完整请求限制为 request_limit。
  """
  @spec validate_request(term()) :: validation()
  def validate_request(%{messages: messages, catalogue: catalogue} = request) do
    with true <- map_size(request) == 2,
         :ok <- Catalogue.validate(catalogue),
         {:ok, _} <- Context.append([], messages),
         :ok <- validate_history(messages, catalogue) do
      if bounded?(request, @limit), do: :ok, else: {:error, :request_limit}
    else
      false -> {:error, :invalid_request}
      error -> error
    end
  end

  def validate_request(_), do: {:error, :invalid_request}

  @doc """
  验证规范消息及完整调用配对：assistant 工具批次后须按原 ID 顺序出现每个 tool 观察，之后才允许下条消息。缺失、孤立和乱序观察返回 invalid_messages。
  """
  @spec validate_history(term(), term()) :: validation()
  def validate_history(messages, catalogue) do
    with :ok <- Catalogue.validate(catalogue),
         {:ok, _} <- Context.append([], messages) do
      history(messages, catalogue)
    end
  end

  @spec history([term()], Catalogue.t()) :: :ok | {:error, :invalid_messages}
  defp history(messages, catalogue) do
    Enum.reduce_while(messages, {:ok, []}, fn message, {:ok, pending} ->
      case next(message, pending, catalogue) do
        {:ok, remaining} -> {:cont, {:ok, remaining}}
        _ -> {:halt, :invalid}
      end
    end)
    |> case do
      {:ok, []} -> :ok
      _ -> {:error, :invalid_messages}
    end
  end

  @spec next(term(), [String.t()], Catalogue.t()) :: {:ok, [String.t()]} | :invalid
  defp next(%{"role" => "tool", "call_id" => id, "content" => text} = m, [id | rest], _) do
    if map_size(m) == 3 and text?(text), do: {:ok, rest}, else: :invalid
  end

  defp next(%{"role" => "assistant", "content" => content, "calls" => calls} = m, [], catalogue) do
    with true <- map_size(m) == 3 and (is_nil(content) or text?(content)),
         {:ok, valid} <- Catalogue.batch(calls, catalogue) do
      {:ok, Enum.map(valid, & &1.id)}
    else
      _ -> :invalid
    end
  end

  defp next(%{"role" => role, "content" => text} = m, [], _)
       when role in ["system", "user", "assistant"] do
    if map_size(m) == 2 and text?(text), do: {:ok, []}, else: :invalid
  end

  defp next(_, _, _), do: :invalid
  @spec text?(term()) :: boolean()
  defp text?(text), do: is_binary(text) and String.valid?(text)

  @doc """
  校验精确的 kind/content/calls 结构、目录、完整 1 MiB JSON 与文本或非空工具批次语义；不接受供应商 wire envelope。保留 invalid_catalogue、response_limit 与 invalid_reply 的区分。
  """
  @spec validate_reply(term(), term()) :: validation()
  def validate_reply(%{kind: kind, content: content, calls: calls} = reply, catalogue) do
    with :ok <- Catalogue.validate(catalogue),
         true <- map_size(reply) == 3,
         {:ok, json} <- encode_reply(reply),
         :ok <- reply_size(json) do
      reply_semantics(kind, content, calls, catalogue)
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :invalid_reply}
    end
  end

  def validate_reply(_, _), do: {:error, :invalid_reply}

  @spec reply_semantics(term(), term(), term(), Catalogue.t()) :: validation()
  defp reply_semantics(kind, content, calls, catalogue) do
    case {kind, content, calls} do
      {:text, text, []} when is_binary(text) ->
        if text?(text), do: :ok, else: {:error, :invalid_reply}

      {:tool_calls, text, calls} when is_binary(text) or is_nil(text) ->
        canonical = if is_list(calls), do: Enum.map(calls, &canonical_call/1), else: nil

        with true <- is_nil(text) or text?(text),
             {:ok, _} <- Catalogue.batch(canonical, catalogue),
             do: :ok,
             else: (_ -> {:error, :invalid_reply})

      _ ->
        {:error, :invalid_reply}
    end
  end

  # 只在编码边界归一化不正规列表异常，保留大小与语义错误优先级。
  # Jason returns errors for most unsupported terms, but raises for improper lists.
  @spec encode_reply(term()) :: {:ok, String.t()} | {:error, term()}
  defp encode_reply(reply) do
    Jason.encode(reply)
  rescue
    FunctionClauseError -> {:error, :invalid_reply}
  end

  @spec reply_size(binary()) :: :ok | {:error, :response_limit}
  defp reply_size(json),
    do: if(byte_size(json) <= @limit, do: :ok, else: {:error, :response_limit})

  @doc """
  把精确的原子键调用转换为字符串键历史调用；形状不符返回 nil，不校验参数。
  """
  @spec canonical_call(term()) :: %{String.t() => term()} | nil
  def canonical_call(%{id: id, name: name, arguments: args} = call) when map_size(call) == 3,
    do: %{"id" => id, "name" => name, "arguments" => args}

  def canonical_call(_), do: nil

  @doc """
  把已经验证的原生回复转换为历史消息。调用前应先 validate_reply/2；此函数本身不验证回复。
  """
  @spec assistant_message(reply()) :: json_object()
  def assistant_message(%{kind: :text, content: text}),
    do: %{"role" => "assistant", "content" => text}

  def assistant_message(%{kind: :tool_calls, content: text, calls: calls}),
    do: %{"role" => "assistant", "content" => text, "calls" => Enum.map(calls, &canonical_call/1)}
end
