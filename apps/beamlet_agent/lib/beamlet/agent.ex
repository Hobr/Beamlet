defmodule Beamlet.Agent do
  @moduledoc "Explicit authority, bounded asynchronous Agents and opt-in paused durable recovery."
  alias Beamlet.Agent.Durable
  alias Beamlet.Agent.History
  alias Beamlet.Agent.Ref
  alias Beamlet.Agent.Server
  alias Beamlet.Agent.Storage.AgentRecords
  alias Beamlet.Agent.TraceExport

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

  @doc "Durable input: the command identity makes a repeated submission replay instead of re-dispatch."
  def input(ref, text, command_id), do: command(ref, {:input, text, command_id})
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

  @doc """
  Loads a paused instance from a durable locator (`%{repo:, agent_id:, model:,
  tools:, catalogue:, environment:, runtime:}`) plus `expected_version` and
  `command_id`; `runtime` is the optional live model/Tool dispatch wiring.
  Performs storage reads/activation, but no model or Tool invocation. Starting the
  live Server requires a valid model binding; missing live configuration rejects
  startup while the durable activation remains paused. For dependency-free,
  read-only reconstruction use `Beamlet.Agent.Durable.inspect/1`. An id that is
  still live returns `{:error, :already_active}` before activation. Old inventoried
  senders must be DOWN before a new generation is activated.
  """
  def restore(locator, expected_version, command_id) do
    with :ok <- inactive(locator),
         {:ok, restored} <- Durable.restore(locator, expected_version, command_id) do
      start_restored(locator, restored)
    end
  end

  defp inactive(%{repo: repo, agent_id: agent_id}) do
    case AgentRecords.fetch(repo, agent_id) do
      {:ok, %{"agent" => %{"alias" => alias_name} = agent}} ->
        if Registry.lookup(Beamlet.Agent.Registry, alias_name || agent["id"]) == [],
          do: :ok,
          else: {:error, :already_active}

      # An unknown Agent is the restore transaction's error to report.
      _ ->
        :ok
    end
  end

  defp inactive(_), do: :ok

  defp start_restored(locator, restored) do
    opts = [
      id: restored.alias || restored.durable.agent_id,
      model: locator[:model],
      tools: Map.get(locator, :tools, %{}),
      catalogue: Map.get(locator, :catalogue, %{}),
      durable: restored.durable,
      restored: %{control: restored.control, durable: restored.durable}
    ]

    case start_local(opts) do
      {:ok, ref} -> {:ok, ref}
      {:error, {:already_started, _pid}} -> {:error, :already_active}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Same-authority reference fork at a safe committed sequence; returns a paused locator."
  def fork(locator, through_seq, expected_version, command_id),
    do: Durable.fork(locator, through_seq, expected_version, command_id)

  @doc "Read-only durable facts, context, operations and provenance without a live Agent."
  def history(locator, filters \\ %{}, cursor \\ nil),
    do: History.query(locator, filters, cursor)

  @doc """
  Bounded trace export of one committed scope: fixes a high-water mark first, then
  streams a versioned manifest, JSONL events/checkpoints and referenced artifacts
  into `policy.dir`. Read-only; the package never grants import/execution.
  """
  def export(locator, scope, policy) when is_map(locator) do
    TraceExport.export(locator[:repo], scope || locator, policy)
  end

  @doc """
  Explicitly continues a paused durable instance: validates the expected version,
  records the decision and advances the stored continuation. Uncertain external
  effects stay blocked until `decisions` names the pending accepted Operation with
  `%{"operation_id" => id, "resolution" => "confirmed_failed" | "confirmed_executed"}`.
  Multiple uncertain siblings require `%{"resolutions" => [decision, ...]}`.
  Neither form authorizes dispatch of a claimed unresolved attempt.
  """
  def continue(ref, expected_version, decisions, command_id),
    do: command(ref, {:continue, expected_version, decisions, command_id})

  def command(%Ref{} = ref, command) do
    GenServer.call(ref.pid, {ref.incarnation, command}, 5000)
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
