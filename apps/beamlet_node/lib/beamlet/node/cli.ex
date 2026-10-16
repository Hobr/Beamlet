defmodule Beamlet.Node.CLI do
  @moduledoc """
  Small IEx/release client over live Agent refs. Watch runs in the subscriber
  process, acknowledges consumed snapshots and never retries business work.
  """
  alias Beamlet.Agent

  @doc "Resolve an explicit node from a trusted, bounded deployment allowlist."
  def authority(name, allowed) when is_binary(name) and is_list(allowed) do
    if length(allowed) <= 32 and name in allowed and byte_size(name) <= 255 and
         Regex.match?(~r/\A[a-zA-Z0-9_-]+@[a-zA-Z0-9_.-]+\z/, name),
       do: {:ok, String.to_atom(name)},
       else: {:error, :invalid_authority}
  end

  def authority(_, _), do: {:error, :invalid_authority}

  def connect(name, allowed) do
    with {:ok, target} <- authority(name, allowed) do
      if Node.connect(target), do: :ok, else: {:error, :unavailable}
    end
  end

  def create(authority, options), do: Agent.start(authority, options)
  def input(ref, text), do: Agent.input(ref, text)
  def snapshot(ref), do: Agent.snapshot(ref)
  def status(ref), do: Agent.snapshot(ref)
  def stop(ref), do: Agent.stop_turn(ref)
  def close(ref), do: Agent.close(ref)

  @doc "Watch up to 256 snapshots for at most 60 seconds; timeout never cancels work."
  def watch(ref, opts \\ [])

  def watch(ref, opts) when is_list(opts) do
    if Keyword.keyword?(opts) and Enum.all?(Keyword.keys(opts), &(&1 in [:timeout, :events])) do
      do_watch(ref, opts)
    else
      {:error, :invalid_watch_options}
    end
  end

  def watch(_, _), do: {:error, :invalid_watch_options}

  defp do_watch(ref, opts) do
    timeout = Keyword.get(opts, :timeout, 5000)
    events = Keyword.get(opts, :events, 64)

    if is_integer(timeout) and timeout in 1..60_000 and is_integer(events) and
         events in 1..256 do
      with :ok <- Agent.subscribe(ref) do
        try do
          watch_events(ref, System.monotonic_time(:millisecond) + timeout, events)
        after
          Agent.unsubscribe(ref)
        end
      end
    else
      {:error, :invalid_watch_options}
    end
  end

  defp watch_events(_ref, _deadline, 0), do: {:error, :event_limit}

  defp watch_events(ref, deadline, remaining) do
    wait = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:beamlet_agent, ^ref, sequence, {:snapshot, snapshot}} ->
        # inspect limits nested collections and strings; printed codepoints are capped.
        display = inspect(snapshot, limit: 40, printable_limit: 2048, pretty: false)
        IO.puts(String.slice(display, 0, 4096))

        case Agent.ack(ref, sequence) do
          :ok ->
            if snapshot.status in [:done, :error, :stopped],
              do: {:ok, snapshot},
              else: watch_events(ref, deadline, remaining - 1)

          error ->
            error
        end
    after
      wait -> {:error, :timeout_or_loss}
    end
  end
end
