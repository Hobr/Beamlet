defmodule Beamlet.Agent do
  @moduledoc "Explicit authority, ephemeral Agents, and bounded asynchronous turn commands."
  alias Beamlet.Agent.{Ref, Server}

  def start(authority, opts) when is_atom(authority) do
    if authority == node(), do: start_local(opts), else: remote_start(authority, opts)
  end

  def start_local(opts) do
    case DynamicSupervisor.start_child(Beamlet.Agent.Agents, {Server, opts}) do
      {:ok, pid} -> GenServer.call(pid, :ref)
      {:error, reason} -> {:error, reason}
    end
  catch
    :exit, _ -> {:error, :authority_unavailable}
  end

  defp remote_start(authority, opts) do
    :erpc.call(authority, __MODULE__, :start_local, [opts], 5000)
  catch
    _, _ -> {:error, :authority_unavailable}
  end

  @doc "Safe observed authority-local identity descriptors; bounded to five seconds."
  defdelegate list(authority), to: Beamlet.Agent.Discovery
  @doc "Obtain the present Server Ref explicitly by authority and ID."
  defdelegate lookup(authority, id), to: Beamlet.Agent.Discovery
  @doc "Attach a listed descriptor, rejecting replacement PID with stale_agent."
  defdelegate lookup(descriptor), to: Beamlet.Agent.Discovery

  def close(ref), do: command(ref, :close)
  def input(ref, text), do: command(ref, {:input, text})
  def delegate(ref, children, opts \\ []), do: command(ref, {:delegate, children, opts})

  def peer_request(ref, target, payload, ttl \\ 30_000),
    do: command(ref, {:peer_request, target, payload, ttl})

  def peer_reply(ref, id, payload), do: command(ref, {:peer_reply, id, payload})
  def peer_take(ref, id), do: command(ref, {:peer_take, id})
  def inbox(ref), do: command(ref, :inbox)
  def snapshot(ref), do: command(ref, :snapshot)

  @doc "Read a bounded replacement display of live context; see Beamlet.Agent.Display."
  def snapshot(ref, opts), do: command(ref, {:snapshot, opts})
  def stop_turn(ref), do: command(ref, :stop)
  def subscribe(ref, sink \\ self()), do: command(ref, {:subscribe, sink})
  @doc "Subscribe to replacement display snapshots using the existing sink-owned ack/2 credits."
  def subscribe(ref, sink, opts), do: command(ref, {:subscribe, sink, opts})

  def unsubscribe(ref, sink \\ self()), do: command(ref, {:unsubscribe, sink})
  def ack(ref, sequence), do: command(ref, {:ack, self(), sequence})

  def command(%Ref{} = ref, command) do
    GenServer.call(ref.pid, {ref.incarnation, command}, 5000)
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
