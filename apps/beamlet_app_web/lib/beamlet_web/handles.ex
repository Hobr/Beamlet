defmodule Beamlet.Web.Handles do
  @moduledoc "VM-local navigation only: 4096 entries, one-hour idle expiry. Never owns Agents."
  use GenServer
  alias Beamlet.Agent
  @idle 3_600_000
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def remember(descriptor) do
    with {:ok, ref} <- Agent.lookup(descriptor) do
      GenServer.call(__MODULE__, {:put, descriptor, ref})
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

  def fetch(handle) when is_binary(handle) and byte_size(handle) == 32 do
    with {:ok, %{descriptor: descriptor, ref: expected}} <-
           GenServer.call(__MODULE__, {:get, handle}),
         {:ok, ref} <- Agent.lookup(descriptor),
         true <- ref == expected do
      {:ok, ref}
    else
      _ -> {:error, :stale_handle}
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

  def fetch(_), do: {:error, :stale_handle}
  @impl true
  def init(state) do
    Process.send_after(self(), :expire, 60_000)
    {:ok, state}
  end

  @impl true
  def handle_call({:put, descriptor, ref}, _, state) do
    state = expire(state)

    if map_size(state) < 4096 do
      handle = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
      entry = %{descriptor: descriptor, ref: ref, touched: now()}
      {:reply, {:ok, handle}, Map.put(state, handle, entry)}
    else
      {:reply, {:error, :handle_limit}, state}
    end
  end

  def handle_call({:get, handle}, _, state) do
    state = expire(state)

    case Map.fetch(state, handle) do
      {:ok, entry} -> {:reply, {:ok, entry}, Map.put(state, handle, %{entry | touched: now()})}
      :error -> {:reply, {:error, :stale_handle}, state}
    end
  end

  @impl true
  def handle_info(:expire, state) do
    Process.send_after(self(), :expire, 60_000)
    {:noreply, expire(state)}
  end

  defp expire(state), do: Map.reject(state, fn {_, e} -> now() - e.touched >= @idle end)
  defp now, do: System.monotonic_time(:millisecond)
end
