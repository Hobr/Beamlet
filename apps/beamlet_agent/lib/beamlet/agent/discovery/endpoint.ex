defmodule Beamlet.Agent.Discovery.Endpoint do
  @moduledoc false
  use GenServer
  alias Beamlet.Agent.Discovery, as: D
  @capacity 256
  @lease 250

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    {:ok, %{authority: Keyword.fetch!(opts, :authority), offers: %{}, active: %{}}}
  end

  @impl true
  def handle_info({:offer, caller, reply}, state) when is_pid(caller) and is_reference(reply) do
    if map_size(state.offers) + map_size(state.active) < @capacity do
      token = make_ref()
      timer = Process.send_after(self(), {:expire, token}, D.budget())
      D.send_safe(reply, {reply, {:offer, self(), token}})
      {:noreply, put_in(state.offers[token], {caller, reply, D.now() + D.budget(), timer})}
    else
      D.send_safe(reply, {reply, {:error, :limit}})
      {:noreply, state}
    end
  end

  def handle_info({:confirm, caller, reply, token, query, budget}, state) do
    {offer, offers} = Map.pop(state.offers, token)
    state = %{state | offers: offers}
    if is_tuple(offer), do: Process.cancel_timer(elem(offer, 3))

    if match?({^caller, ^reply, _, _}, offer) and elem(offer, 2) > D.now() and
         is_integer(budget) and budget > 0 and budget <= D.budget() and valid_query?(query) do
      if state.authority do
        pid =
          :proc_lib.spawn_link(__MODULE__, :controller, [self(), reply, query, D.now() + budget])

        {:noreply, put_in(state.active[pid], true)}
      else
        D.send_safe(reply, {reply, {:error, :not_authority}})
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:expire, token}, state),
    do: {:noreply, %{state | offers: Map.delete(state.offers, token)}}

  def handle_info({:EXIT, pid, _}, state),
    do: {:noreply, %{state | active: Map.delete(state.active, pid)}}

  def handle_info(_, state), do: {:noreply, state}

  defp valid_query?(:list), do: true

  defp valid_query?({:lookup, id, expected}),
    do: D.valid_id?(id) and (is_nil(expected) or (is_pid(expected) and node(expected) == node()))

  defp valid_query?(_), do: false

  def controller(_endpoint, reply, query, deadline) do
    # Admission stays passive until a fresh challenge succeeds. Deadlines use
    # only this node's clock; reported durations lose the full local roundtrip.
    case fresh_deadline(reply, deadline) do
      {:ok, deadline} -> run_query(reply, query, deadline)
      :expired -> :ok
    end
  end

  defp fresh_deadline(reply, deadline) do
    sent = D.now()
    token = make_ref()

    if D.remaining(deadline) > 0 do
      D.send_safe(reply, {reply, {:ping, self(), token}})

      receive do
        {:pong, ^token, budget} when is_integer(budget) and budget > 0 and budget <= 5000 ->
          received = D.now()
          elapsed = received - sent
          fresh = min(deadline, sent + budget)

          if elapsed < @lease and received < fresh,
            do: {:ok, fresh},
            else: :expired
      after
        min(@lease, D.remaining(deadline)) -> :expired
      end
    else
      :expired
    end
  end

  defp run_query(reply, query, deadline) do
    parent = self()

    {worker, monitor} =
      :erlang.spawn_opt(
        fn ->
          if D.remaining(deadline) > 0,
            do: send(parent, {:result, D.local(query, deadline)})
        end,
        [:link, :monitor]
      )

    try do
      supervise(reply, worker, monitor, deadline)
    after
      Process.unlink(worker)
      Process.exit(worker, :kill)

      receive do
        {:DOWN, ^monitor, _, _, _} -> :ok
      end
    end
  end

  defp supervise(reply, worker, monitor, deadline) do
    receive do
      {:result, result} ->
        safe = if :erlang.external_size(result) <= D.bytes(), do: result, else: {:error, :limit}
        if D.remaining(deadline) > 0, do: D.send_safe(reply, {reply, safe})
    after
      min(50, D.remaining(deadline)) ->
        case fresh_deadline(reply, deadline) do
          {:ok, deadline} -> supervise(reply, worker, monitor, deadline)
          :expired -> D.send_safe(reply, {reply, {:error, :timeout}})
        end
    end
  end
end
