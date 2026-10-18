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
  `command_id`; `runtime` is the optional live Tool dispatch wiring.
  Performs no model, Tool or network work; a missing dependency returns
  `{:error, {:blocked, reason}}` before any instance exists. An id that is still
  live returns `{:error, :already_active}` before the restore transaction, so a
  rejected duplicate never bumps the generation of the running instance.
  """
  def restore(locator, expected_version, command_id) do
    with :ok <- inactive(locator),
         {:ok, restored} <- Beamlet.Agent.Durable.restore(locator, expected_version, command_id) do
      start_restored(locator, restored)
    end
  end

  defp inactive(%{repo: repo, agent_id: agent_id}) do
    case Beamlet.Storage.AgentRecords.fetch(repo, agent_id) do
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
      restored: %{checkpoint: restored.checkpoint, durable: restored.durable}
    ]

    case start_local(opts) do
      {:ok, ref} -> {:ok, ref}
      {:error, {:already_started, _pid}} -> {:error, :already_active}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Copies a safe checkpoint of the source Agent into a new independent Agent and
  returns its locator (`%{agent_id:, checkpoint_id:, locator:, source:, risk:,
  copied:, version:, generation:}`). The source locator, Ref and alias keep
  pointing at the source; the caller must use the returned locator explicitly.

  The local source instance must be retired first: a still-registered source is
  refused with `{:error, :source_not_frozen}`, because a live local dispatcher is
  not a frozen source. The fork writes no row of the source Agent, its checkpoints or
  its events; the one exception is the fork command receipt, which is stored in the
  source's command namespace so a retried command returns the same locator. See
  `Beamlet.Agent.Durable.fork/4` for `locator.source` and the risk rule.
  """
  def fork(locator, checkpoint_id, expected_version, command_id) do
    with :ok <- dormant_source(locator) do
      Beamlet.Agent.Durable.fork(locator, checkpoint_id, expected_version, command_id)
    end
  end

  defp dormant_source(%{repo: repo, agent_id: agent_id}) do
    case Beamlet.Storage.AgentRecords.fetch(repo, agent_id) do
      {:ok, %{"agent" => %{"alias" => alias_name} = agent}} ->
        if Registry.lookup(Beamlet.Agent.Registry, alias_name || agent["id"]) == [],
          do: :ok,
          else: {:error, :source_not_frozen}

      # An unknown source is the fork transaction's error to report.
      _ ->
        :ok
    end
  end

  defp dormant_source(_), do: :ok

  @doc """
  Read-only durable history of a locator (`%{repo:, agent_id:}`) without starting
  or contacting an Agent: `view: :turns | :facts | :context | :steps | :tools |
  :evidence | :decisions | :provenance`. Current runtime observation is not part
  of history and stays with `Beamlet.Runtime.status/1`.
  """
  def history(locator, filters \\ %{}, cursor \\ nil),
    do: Beamlet.Agent.History.query(locator, filters, cursor)

  @doc """
  Bounded trace export of one committed scope: fixes a high-water mark first, then
  streams a versioned manifest, JSONL events/checkpoints and referenced artifacts
  into `policy.dir`. Read-only; the package never grants import/execution.
  """
  def export(locator, scope, policy) when is_map(locator) do
    Beamlet.Agent.TraceExport.export(locator[:repo], scope || locator, policy)
  end

  @doc """
  Explicitly continues a paused durable instance: validates the expected version,
  records the decision and advances the stored continuation. Uncertain external
  effects stay blocked until `decisions` carries `%{"resolution" => "confirmed_failed" | "confirmed_executed"}`.
  """
  def continue(ref, expected_version, decisions, command_id),
    do: command(ref, {:continue, expected_version, decisions, command_id})

  def command(%Ref{} = ref, command) do
    GenServer.call(ref.pid, {ref.incarnation, command}, 5000)
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
