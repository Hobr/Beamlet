defmodule Beamlet.Node.Cluster do
  @moduledoc """
  Trusted deployment names and explicit distribution connections, independent of hosts.

  All names must be ASCII node@host strings of at most 255 bytes in an allowlist
  of at most 32 names. Only a validated, explicitly allowed name is atomized.
  Connections are attempted once, with a five-second receive budget; no business
  work is submitted or retried. OTP may finish a handshake after that budget.
  """

  @doc "Resolve an explicit node from a trusted, bounded deployment allowlist."
  def authority(name, allowed) do
    if valid_allowlist?(allowed) and valid_name?(name) and name in allowed,
      do: {:ok, String.to_atom(name)},
      else: {:error, :invalid_authority}
  end

  @doc "Attempt one connection; failure or timeout returns unavailable."
  def connect(name, allowed) do
    with {:ok, target} <- authority(name, allowed) do
      # The stream controller owns the single helper and kills it on timeout or
      # caller loss. Do not leave an unbounded Node.connect call in a host callback.
      case Enum.to_list(
             Task.async_stream([target], &Node.connect/1,
               max_concurrency: 1,
               timeout: 5000,
               on_timeout: :kill_task
             )
           ) do
        [{:ok, true}] -> :ok
        _ -> {:error, :unavailable}
      end
    end
  end

  @doc """
  Return already connected trusted nodes, including this VM only if alive and
  allowlisted. Does not atomize the allowlist or establish any connections.
  """
  def connected(allowed) do
    if valid_allowlist?(allowed) do
      nodes = if Node.alive?(), do: [node() | Node.list(:connected)], else: []
      {:ok, nodes |> Enum.filter(&(Atom.to_string(&1) in allowed)) |> Enum.sort()}
    else
      {:error, :invalid_authority}
    end
  end

  defp valid_allowlist?(allowed), do: valid_allowlist?(allowed, 32)
  defp valid_allowlist?([], _remaining), do: true

  defp valid_allowlist?([name | rest], remaining) when remaining > 0,
    do: valid_name?(name) and valid_allowlist?(rest, remaining - 1)

  defp valid_allowlist?(_, _remaining), do: false

  defp valid_name?(name) when is_binary(name),
    do:
      byte_size(name) in 3..255 and
        Regex.match?(~r/\A[a-zA-Z0-9_-]+@[a-zA-Z0-9_.-]+\z/, name)

  defp valid_name?(_), do: false
end
