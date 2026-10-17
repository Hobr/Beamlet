defmodule Beamlet.Harness.Model do
  @moduledoc "Provider-neutral bounded model contracts and trusted local provider registration."
  alias Beamlet.Harness.{Catalogue, Context}
  @limit 1_048_576
  @callback validate_invocation(map()) :: :ok | {:error, atom()}
  @callback complete(map(), map(), Context.t()) :: {:ok, map()} | {:error, atom()}

  def default_providers do
    %{
      "openai-compatible" => Beamlet.Harness.Models.OpenAICompatible,
      "deterministic" => Beamlet.Harness.Models.Deterministic
    }
  end

  def provider_id?(id), do: Catalogue.name?(id)

  def validate_registry(registry)
      when is_map(registry) and not is_struct(registry) and map_size(registry) <= 32 do
    if Enum.all?(registry, fn {id, module} ->
         provider_id?(id) and is_atom(module) and Code.ensure_loaded?(module) and
           function_exported?(module, :validate_invocation, 1) and
           function_exported?(module, :complete, 3)
       end), do: :ok, else: {:error, :invalid_model_providers}
  end

  def validate_registry(_), do: {:error, :invalid_model_providers}

  # JSON validation deliberately does not use Jason's atom-key coercion.
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

  def validate_invocation(%{config: config, credentials: credentials} = invocation) do
    if map_size(invocation) == 2 and valid_config?(config) and valid_credentials?(credentials),
      do: :ok,
      else: {:error, :invalid_invocation}
  end

  def validate_invocation(_), do: {:error, :invalid_invocation}

  defp valid_config?(config),
    do: object?(config) and ordinary?(config) and bounded?(config, 16_384)

  defp valid_credentials?(credentials),
    do:
      object?(credentials) and map_size(credentials) <= 32 and
        Enum.all?(Map.keys(credentials), &(byte_size(&1) in 1..128)) and
        no_roots?(credentials) and bounded?(credentials, 16_384)

  defp object?(value), do: is_map(value) and not is_struct(value) and json?(value)

  defp ordinary?(value) when is_map(value) do
    Enum.all?(value, fn {k, v} ->
      String.downcase(k) not in ~w(api_key token credential credentials secret password authorization root workspace_root) and
        ordinary?(v)
    end)
  end

  defp ordinary?(value) when is_list(value), do: Enum.all?(value, &ordinary?/1)
  defp ordinary?(_), do: true

  defp no_roots?(value) when is_map(value),
    do:
      Enum.all?(value, fn {k, v} ->
        String.downcase(k) not in ~w(root workspace_root) and no_roots?(v)
      end)

  defp no_roots?(value) when is_list(value), do: Enum.all?(value, &no_roots?/1)
  defp no_roots?(_), do: true

  defp bounded?(value, limit) do
    case Jason.encode(value) do
      {:ok, json} -> byte_size(json) <= limit
      _ -> false
    end
  end

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

  def validate_history(messages, catalogue) do
    with :ok <- Catalogue.validate(catalogue),
         {:ok, _} <- Context.append([], messages) do
      history(messages, catalogue)
    end
  end

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
  defp text?(text), do: is_binary(text) and String.valid?(text)

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

  # Jason returns errors for most unsupported terms, but raises for improper lists.
  defp encode_reply(reply) do
    Jason.encode(reply)
  rescue
    FunctionClauseError -> {:error, :invalid_reply}
  end

  defp reply_size(json),
    do: if(byte_size(json) <= @limit, do: :ok, else: {:error, :response_limit})

  def canonical_call(%{id: id, name: name, arguments: args} = call) when map_size(call) == 3,
    do: %{"id" => id, "name" => name, "arguments" => args}

  def canonical_call(_), do: nil

  def assistant_message(%{kind: :text, content: text}),
    do: %{"role" => "assistant", "content" => text}

  def assistant_message(%{kind: :tool_calls, content: text, calls: calls}),
    do: %{"role" => "assistant", "content" => text, "calls" => Enum.map(calls, &canonical_call/1)}
end
