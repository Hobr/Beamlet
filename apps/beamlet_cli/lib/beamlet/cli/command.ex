defmodule Beamlet.CLI.Command do
  @moduledoc "Bounded UTF-8 command grammar. Executable input is never truncated."
  @max_bytes 65_536
  def max_bytes, do: @max_bytes

  def parse(line) when is_binary(line) and byte_size(line) <= @max_bytes do
    if String.valid?(line), do: parse_words(String.trim_trailing(line, "\n")), else: error()
  end

  def parse(_), do: error()
  defp error, do: {:error, :invalid_command}

  defp parse_words(line) do
    case String.split(line, ~r/\s+/, parts: 3, trim: true) do
      ["input", name, text] when byte_size(text) > 0 -> {:ok, {:input, name, text}}
      _ -> words(String.split(line))
    end
  end

  defp words([command]) when command in ~w(help nodes quit), do: {:ok, {command}}
  defp words(["agents"]), do: {:ok, {:agents, nil}}
  defp words(["agents", authority]), do: {:ok, {:agents, authority}}

  defp words(["agents-page", page]) do
    case Integer.parse(page) do
      {n, ""} when n > 0 -> {:ok, {:agents_page, n}}
      _ -> error()
    end
  end

  defp words(["connect", authority]), do: {:ok, {:connect, authority}}
  defp words(["create", authority, path]), do: {:ok, {:create, authority, path}}
  defp words(["attach", authority, id]), do: attach(authority, id, id)
  defp words(["attach", authority, id, name]), do: attach(authority, id, name)

  defp words([command, name]) when command in ~w(status stop close detach),
    do: {:ok, {command, name}}

  defp words(["watch", name]), do: {:ok, {:watch, name, []}}

  defp words(["watch", name, timeout]), do: words(["watch", name, timeout, "64"])

  defp words(["watch", name, timeout, events]) do
    with {ms, ""} <- Integer.parse(timeout),
         {count, ""} <- Integer.parse(events),
         true <- ms in 1..60_000 and count in 1..256 do
      {:ok, {:watch, name, [timeout: ms, events: count]}}
    else
      _ -> error()
    end
  end

  defp words(_), do: error()
  def identity_token(id), do: "id64:" <> Base.url_encode64(id, padding: false)

  defp attach(authority, "id64:" <> encoded, name) do
    with {:ok, id} <- Base.url_decode64(encoded, padding: false),
         true <- byte_size(id) in 1..128 and String.valid?(id) do
      {:ok, {:attach, authority, id, name}}
    else
      _ -> error()
    end
  end

  defp attach(authority, id, name), do: {:ok, {:attach, authority, id, name}}
end
