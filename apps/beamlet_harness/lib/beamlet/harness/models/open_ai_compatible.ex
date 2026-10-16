defmodule Beamlet.Harness.Models.OpenAICompatible do
  @moduledoc "Executor-local, nonstreaming text Chat Completions subset. Never retries."
  @behaviour Beamlet.Harness.Model
  alias Beamlet.Harness.{Catalogue, Context}
  @limit 1_048_576

  @impl true
  def complete(request, settings, context \\ %Context{}) do
    with false <- Context.cancelled?(context),
         {:ok, url, key} <- profile(settings),
         {:ok, payload} <- payload(request, settings),
         {:ok, response} <- transport(url, key, payload, settings) do
      decode(response, request.catalogue)
    else
      true -> {:error, :cancelled}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :transport}
    end
  rescue
    _ -> {:error, :provider_failure}
  end

  defp profile(%{base_url: base, model: model, key_env: env} = settings)
       when is_binary(base) and is_binary(model) and is_binary(env) do
    uri = URI.parse(base)

    key = System.get_env(env)

    if safe_settings?(settings) and safe_base?(base) and
         safe_uri?(uri, settings) and safe_key?(key) and byte_size(model) in 1..256 and
         String.valid?(model) do
      {:ok, String.trim_trailing(base, "/") <> "/chat/completions", key}
    else
      {:error, :invalid_profile}
    end
  end

  defp profile(_), do: {:error, :invalid_profile}

  defp safe_settings?(settings) do
    Map.keys(settings) -- [:base_url, :model, :key_env, :timeout_ms, :allow_local_http] == [] and
      is_boolean(Map.get(settings, :allow_local_http, false)) and
      is_integer(Map.get(settings, :timeout_ms, 5000)) and
      Map.get(settings, :timeout_ms, 5000) in 1..60_000
  end

  defp safe_base?(base) do
    String.valid?(base) and not String.contains?(base, ["\\", <<0>>, "\r", "\n", " "])
  end

  defp safe_uri?(uri, settings) do
    local_http =
      uri.scheme == "http" and uri.host in ["127.0.0.1", "localhost", "::1"] and
        Map.get(settings, :allow_local_http, false)

    (uri.scheme == "https" or local_http) and safe_host?(uri) and
      uri.userinfo == nil and uri.query == nil and uri.fragment == nil
  end

  defp safe_host?(uri),
    do: is_binary(uri.host) and uri.host != "" and uri.port in 1..65_535

  defp safe_key?(key),
    do: is_binary(key) and byte_size(key) in 1..4096 and not String.contains?(key, ["\r", "\n"])

  def validate_request(%{messages: messages, catalogue: catalogue} = request) do
    with true <- Map.keys(request) -- [:messages, :catalogue] == [],
         :ok <- Catalogue.validate(catalogue),
         {:ok, _} <- Context.append([], messages),
         :ok <- messages_valid(messages, catalogue) do
      case Jason.encode(request) do
        {:ok, json} when byte_size(json) <= @limit -> :ok
        _ -> {:error, :request_limit}
      end
    else
      false -> {:error, :invalid_request}
      error -> error
    end
  end

  def validate_request(_), do: {:error, :invalid_request}

  defp payload(%{messages: messages, catalogue: catalogue} = request, settings) do
    with :ok <- validate_request(request) do
      tools =
        Enum.map(Enum.sort_by(catalogue, &elem(&1, 0)), fn {_, d} ->
          %{"type" => "function", "function" => d}
        end)

      body = %{model: settings.model, messages: messages, stream: false, n: 1}
      body = if tools == [], do: body, else: Map.put(body, :tools, tools)

      with {:ok, json} <- Jason.encode(body),
           true <- byte_size(json) <= @limit,
           do: {:ok, json},
           else: (_ -> {:error, :request_limit})
    end
  end

  defp payload(_, _), do: {:error, :invalid_request}

  defp messages_valid(messages, catalogue) do
    Enum.reduce_while(messages, {:ok, []}, fn m, {:ok, pending} ->
      case message_pending(m, pending, catalogue) do
        {:ok, next} -> {:cont, {:ok, next}}
        _ -> {:halt, :invalid}
      end
    end)
    |> case do
      {:ok, []} -> :ok
      _ -> {:error, :invalid_messages}
    end
  end

  defp message_pending(
         %{"role" => "tool", "tool_call_id" => id, "content" => text} = m,
         [id | rest],
         _
       )
       when is_binary(text) do
    if Map.keys(m) -- ~w(role tool_call_id content) == [], do: {:ok, rest}, else: :invalid
  end

  defp message_pending(%{"role" => "assistant", "tool_calls" => _} = m, [], catalogue) do
    case normalize(
           %{"choices" => [%{"finish_reason" => "tool_calls", "message" => m}]},
           catalogue
         ) do
      {:ok, %{calls: valid}} -> {:ok, Enum.map(valid, & &1.id)}
      _ -> :invalid
    end
  end

  defp message_pending(%{"role" => role, "content" => text} = m, [], _)
       when role in ["system", "user", "assistant"] and is_binary(text) do
    if Map.keys(m) -- ~w(role content) == [], do: {:ok, []}, else: :invalid
  end

  defp message_pending(_, _, _), do: :invalid

  defp transport(url, key, body, settings) do
    timeout = Map.get(settings, :timeout_ms, 5000)

    if not is_integer(timeout) or timeout not in 1..60_000 do
      {:error, :invalid_profile}
    else
      request = Req.Request.new() |> Req.Steps.attach()

      Req.post(request,
        url: url,
        body: body,
        auth: {:bearer, key},
        headers: [{"content-type", "application/json"}, {"accept-encoding", "identity"}],
        retry: false,
        redirect: false,
        raw: true,
        compressed: false,
        receive_timeout: timeout,
        request_timeout: timeout,
        connect_options: [timeout: timeout, transport_opts: [verify: :verify_peer]],
        into: &collect/2
      )
    end
  end

  defp collect({:data, chunk}, {request, response}) do
    size = Map.get(response.private, :body_bytes, 0) + byte_size(chunk)

    if size > @limit do
      {:halt, {request, %{response | private: Map.put(response.private, :body_overflow, true)}}}
    else
      private =
        response.private
        |> Map.put(:body_bytes, size)
        |> Map.update(:chunks, [chunk], &[chunk | &1])

      {:cont, {request, %{response | private: private}}}
    end
  end

  defp decode(response, catalogue) do
    cond do
      response.private[:body_overflow] ->
        {:error, :response_limit}

      Req.Response.get_header(response, "content-encoding") not in [[], ["identity"]] ->
        {:error, :unsupported_encoding}

      response.status not in 200..299 ->
        {:error, :http_status}

      true ->
        body = response.private |> Map.get(:chunks, []) |> Enum.reverse() |> IO.iodata_to_binary()

        case Jason.decode(body) do
          {:ok, value} -> normalize(value, catalogue)
          _ -> {:error, :invalid_json}
        end
    end
  end

  defp normalize_reply(
         %{
           "choices" => [
             %{"finish_reason" => finish, "message" => %{"role" => "assistant"} = message} =
               choice
           ]
         } = envelope,
         catalogue
       ) do
    with true <-
           Map.keys(envelope) --
             ~w(choices id object created model usage system_fingerprint service_tier) == [],
         true <- Map.keys(choice) -- ~w(finish_reason message index logprobs) == [],
         :ok <- safe_message(message),
         {:ok, reply} <- finish(finish, message, catalogue) do
      if byte_size(Jason.encode!(reply)) <= @limit,
        do: {:ok, reply},
        else: {:error, :response_limit}
    else
      false -> {:error, :unsupported_reply}
      error -> error
    end
  end

  defp normalize_reply(_, _), do: {:error, :invalid_reply}

  def normalize(reply, catalogue) do
    with :ok <- Catalogue.validate(catalogue),
         {:ok, json} <- Jason.encode(reply),
         true <- byte_size(json) <= @limit do
      normalize_reply(reply, catalogue)
    else
      false -> {:error, :response_limit}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :invalid_reply}
    end
  end

  defp safe_message(message) do
    cond do
      Map.keys(message) -- ~w(role content tool_calls refusal) != [] ->
        {:error, :unsupported_reply}

      message["refusal"] not in [nil, ""] ->
        {:error, :refused}

      safe_content?(message["content"]) ->
        :ok

      true ->
        {:error, :invalid_reply}
    end
  end

  defp safe_content?(nil), do: true

  defp safe_content?(content),
    do: is_binary(content) and String.valid?(content) and byte_size(content) <= @limit

  defp finish("stop", %{"content" => text} = message, _) when is_binary(text) do
    if message["tool_calls"] in [nil, []],
      do: {:ok, %{kind: :text, content: text, calls: [], assistant: message}},
      else: {:error, :unsupported_reply}
  end

  defp finish("tool_calls", message, catalogue) do
    with {:ok, calls} <- Catalogue.batch(message["tool_calls"], catalogue) do
      {:ok, %{kind: :tool_calls, content: message["content"], calls: calls, assistant: message}}
    end
  end

  defp finish(reason, _, _) when reason in ["length", "content_filter"],
    do: {:error, :incomplete_reply}

  defp finish(_, _, _), do: {:error, :unsupported_reply}
end
