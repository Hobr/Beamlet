defmodule Beamlet.Harness.Models.OpenAICompatible do
  @moduledoc "Nonstreaming text Chat Completions adapter using Agent-owned invocation config and credentials. Never retries."
  @behaviour Beamlet.Harness.Model
  alias Beamlet.Harness.{Catalogue, Context, Model}
  @limit 1_048_576

  @impl true
  def complete(request, settings, context \\ %Context{}) do
    with false <- Context.cancelled?(context),
         :ok <- validate_invocation(settings),
         {:ok, url, key} <- profile(settings),
         {:ok, payload} <- payload(request, settings.config),
         {:ok, response} <- transport(url, key, payload, settings.config) do
      decode(response, request.catalogue)
    else
      true -> {:error, :cancelled}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :transport}
    end
  rescue
    _ -> {:error, :provider_failure}
  end

  @impl true
  def validate_invocation(invocation) do
    with :ok <- Model.validate_invocation(invocation), {:ok, _, _} <- profile(invocation) do
      :ok
    else
      _ -> {:error, :invalid_profile}
    end
  rescue
    _ -> {:error, :invalid_profile}
  end

  defp profile(%{
         config: %{"base_url" => base, "model" => model} = config,
         credentials: %{"api_key" => key} = credentials
       })
       when is_binary(base) and is_binary(model) do
    uri = URI.parse(base)

    if map_size(credentials) == 1 and safe_settings?(config) and safe_base?(base) and
         safe_uri?(uri, config) and safe_key?(key) and byte_size(model) in 1..256 and
         String.valid?(model) do
      {:ok, String.trim_trailing(base, "/") <> "/chat/completions", key}
    else
      {:error, :invalid_profile}
    end
  end

  defp profile(_), do: {:error, :invalid_profile}

  defp safe_settings?(settings) do
    Map.keys(settings) -- ~w(base_url model timeout_ms allow_local_http) == [] and
      is_boolean(Map.get(settings, "allow_local_http", false)) and
      is_integer(Map.get(settings, "timeout_ms", 5000)) and
      Map.get(settings, "timeout_ms", 5000) in 1..60_000
  end

  defp safe_base?(base) do
    String.valid?(base) and not String.contains?(base, ["\\", <<0>>, "\r", "\n", " "])
  end

  defp safe_uri?(uri, settings) do
    local_http =
      uri.scheme == "http" and uri.host in ["127.0.0.1", "localhost", "::1"] and
        Map.get(settings, "allow_local_http", false)

    (uri.scheme == "https" or local_http) and safe_host?(uri) and
      uri.userinfo == nil and uri.query == nil and uri.fragment == nil
  end

  defp safe_host?(uri),
    do: is_binary(uri.host) and uri.host != "" and uri.port in 1..65_535

  defp safe_key?(key),
    do:
      is_binary(key) and byte_size(key) in 1..4096 and String.valid?(key) and
        not String.contains?(key, ["\r", "\n"])

  defp payload(%{messages: messages, catalogue: catalogue} = request, settings) do
    with :ok <- Model.validate_request(request) do
      tools =
        Enum.map(Enum.sort_by(catalogue, &elem(&1, 0)), fn {_, d} ->
          %{"type" => "function", "function" => d}
        end)

      body = %{
        model: settings["model"],
        messages: Enum.map(messages, &encode_message/1),
        stream: false,
        n: 1
      }

      body = if tools == [], do: body, else: Map.put(body, :tools, tools)

      with {:ok, json} <- Jason.encode(body),
           true <- byte_size(json) <= @limit,
           do: {:ok, json},
           else: (_ -> {:error, :request_limit})
    end
  end

  defp payload(_, _), do: {:error, :invalid_request}

  defp encode_message(%{"role" => "assistant", "calls" => calls} = message) do
    message
    |> Map.delete("calls")
    |> Map.put(
      "tool_calls",
      Enum.map(calls, fn call ->
        %{
          "id" => call["id"],
          "type" => "function",
          "function" => %{"name" => call["name"], "arguments" => Jason.encode!(call["arguments"])}
        }
      end)
    )
  end

  defp encode_message(%{"role" => "tool", "call_id" => id} = message),
    do: message |> Map.delete("call_id") |> Map.put("tool_call_id", id)

  defp encode_message(message), do: message

  defp decode_calls(calls) when is_list(calls) do
    Enum.reduce_while(calls, {:ok, []}, fn call, {:ok, acc} ->
      with %{
             "id" => id,
             "type" => "function",
             "function" => %{"name" => name, "arguments" => raw} = function
           } <- call,
           true <- map_size(call) == 3 and map_size(function) == 2,
           true <- is_binary(raw) and byte_size(raw) <= 16_384,
           {:ok, args} <- Jason.decode(raw) do
        {:cont, {:ok, [%{"id" => id, "name" => name, "arguments" => args} | acc]}}
      else
        _ -> {:halt, {:error, :invalid_tool_batch}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp decode_calls(_), do: {:error, :invalid_tool_batch}

  defp transport(url, key, body, settings) do
    timeout = Map.get(settings, "timeout_ms", 5000)

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
         {:ok, json} <- encode_reply(reply),
         true <- byte_size(json) <= @limit do
      normalize_reply(reply, catalogue)
    else
      false -> {:error, :response_limit}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :invalid_reply}
    end
  end

  # Direct callers can supply terms that cannot occur in decoded JSON.
  defp encode_reply(reply) do
    Jason.encode(reply)
  rescue
    FunctionClauseError -> {:error, :invalid_reply}
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
      do: {:ok, %{kind: :text, content: text, calls: []}},
      else: {:error, :unsupported_reply}
  end

  defp finish("tool_calls", message, catalogue) do
    with {:ok, decoded} <- decode_calls(message["tool_calls"]),
         {:ok, calls} <- Catalogue.batch(decoded, catalogue) do
      {:ok, %{kind: :tool_calls, content: message["content"], calls: calls}}
    end
  end

  defp finish(reason, _, _) when reason in ["length", "content_filter"],
    do: {:error, :incomplete_reply}

  defp finish(_, _, _), do: {:error, :unsupported_reply}
end
