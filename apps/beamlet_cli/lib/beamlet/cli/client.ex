defmodule Beamlet.CLI.Client do
  @moduledoc """
  Small IEx/release client over live Agent refs. Watch runs in the subscriber
  process, acknowledges consumed snapshots and never retries business work.
  """
  alias Beamlet.Agent
  alias Beamlet.CLI.Renderer

  @typep output :: (binary() -> term())
  @typep watch_result :: Agent.result(Agent.snapshot())
  @spec create(node(), term()) :: Agent.result(Agent.Ref.t())
  def create(authority, options), do: Agent.start(authority, options)
  @spec input(Agent.Ref.t(), term()) :: Agent.result(Agent.turn())
  def input(ref, text), do: Agent.input(ref, text)
  @spec snapshot(Agent.Ref.t()) :: Agent.result(Agent.snapshot())
  def snapshot(ref), do: Agent.snapshot(ref)
  @spec status(Agent.Ref.t()) :: Agent.result(Agent.snapshot())
  def status(ref), do: Agent.snapshot(ref)
  @spec stop(Agent.Ref.t()) :: :ok | Agent.error()
  def stop(ref), do: Agent.stop_turn(ref)
  @spec close(Agent.Ref.t()) :: :ok | Agent.error()
  def close(ref), do: Agent.close(ref)

  @doc "Watch up to 256 snapshots for at most 60 seconds; timeout never cancels work."
  @spec watch(Agent.Ref.t(), term()) :: watch_result()
  def watch(ref, opts \\ [])

  def watch(ref, opts) when is_list(opts) do
    if Keyword.keyword?(opts) and
         Enum.all?(Keyword.keys(opts), &(&1 in [:timeout, :events, :output])) do
      do_watch(ref, opts)
    else
      {:error, :invalid_watch_options}
    end
  end

  def watch(_, _), do: {:error, :invalid_watch_options}

  @spec do_watch(Agent.Ref.t(), keyword()) :: watch_result()
  defp do_watch(ref, opts) do
    timeout = Keyword.get(opts, :timeout, 5000)
    events = Keyword.get(opts, :events, 64)

    if is_integer(timeout) and timeout in 1..60_000 and is_integer(events) and
         events in 1..256 and is_function(Keyword.get(opts, :output, &Owl.IO.puts/1), 1) do
      with :ok <- Agent.subscribe(ref) do
        try do
          watch_events(
            ref,
            System.monotonic_time(:millisecond) + timeout,
            events,
            Keyword.get(opts, :output, &Owl.IO.puts/1)
          )
        after
          Agent.unsubscribe(ref)
        end
      end
    else
      {:error, :invalid_watch_options}
    end
  end

  @spec watch_events(Agent.Ref.t(), integer(), non_neg_integer(), output()) :: watch_result()
  defp watch_events(_ref, _deadline, 0, _output), do: {:error, :event_limit}

  defp watch_events(ref, deadline, remaining, output) do
    wait = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:beamlet_agent, ^ref, sequence, {:snapshot, snapshot}} ->
        # Same safe domain projection as status; Owl bounds per-event display.
        display = Renderer.render(snapshot)

        output.(
          display
          |> Owl.Data.truncate(4096)
          |> Owl.Data.to_chardata()
          |> IO.chardata_to_string()
          |> String.to_charlist()
          |> Enum.take(4096)
          |> List.to_string()
        )

        case Agent.ack(ref, sequence) do
          :ok ->
            if snapshot.status in [:done, :error, :stopped],
              do: {:ok, snapshot},
              else: watch_events(ref, deadline, remaining - 1, output)

          error ->
            error
        end
    after
      wait -> {:error, :timeout_or_loss}
    end
  end
end
