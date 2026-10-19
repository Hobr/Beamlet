defmodule Beamlet.Agent.Delegation do
  @typep spec :: Beamlet.Agent.child_specification()
  @typep outcome :: :ok | Beamlet.Agent.error()
  @spec launch(pid(), reference(), non_neg_integer(), spec(), pid()) :: :ok
  @spec admit(pid(), reference(), non_neg_integer(), spec(), pid()) :: :ok | tuple()
  @spec relay(pid(), reference(), pid(), reference()) :: :ok
  @spec run(pid(), reference(), non_neg_integer(), spec()) ::
          Beamlet.Agent.command_result() | tuple()
  @spec startup(reference()) :: outcome()
  @spec startup_clear() :: outcome()
  @spec await(
          pid(),
          reference(),
          reference(),
          reference(),
          non_neg_integer(),
          Beamlet.Agent.Ref.t(),
          Beamlet.Agent.turn()
        ) :: Beamlet.Agent.command_result() | tuple()
  @spec finish(
          pid(),
          reference(),
          non_neg_integer(),
          Beamlet.Agent.Ref.t(),
          Beamlet.Agent.turn(),
          Beamlet.Agent.result(term())
        ) :: tuple()
  @spec cleanup(Beamlet.Agent.Ref.t()) :: :ok | Beamlet.Agent.error()
  @moduledoc false
  alias Beamlet.Agent.Lifecycle
  # One bounded helper per owned child, never one per subscriber or event.
  # All waits occur here, outside the Agent callback. Each child monitors its delegator.
  def launch(parent, group, id, spec, authority) do
    Lifecycle.run(
      parent,
      fn controller ->
        admit(parent, group, id, spec, controller)
      end,
      authority,
      :delegation
    )
  end

  defp admit(parent, group, id, spec, controller) do
    pm = Process.monitor(parent)
    launcher = self()

    case Task.Supervisor.start_child(Beamlet.Agent.Delegations, fn ->
           Process.link(launcher)
           Process.link(controller)
           send(controller, {:owned, self()})
           run(parent, group, id, Map.put(spec, :launcher, controller))
         end) do
      {:ok, helper} ->
        cm = Process.monitor(helper)
        relay(parent, pm, helper, cm)

      _ ->
        send(parent, {:delegation_result, group, id, nil, nil, {:error, :delegation_capacity}})
    end
  end

  defp relay(parent, pm, helper, cm) do
    receive do
      :stop ->
        send(helper, :stop)
        relay(parent, pm, helper, cm)

      {:DOWN, ^pm, _, _, _} ->
        send(helper, :stop)
        relay(parent, pm, helper, cm)

      {:DOWN, ^cm, _, _, _} ->
        :ok

      {:child_startup, ^helper, group, ticket} ->
        send(parent, {:child_startup, self(), group, ticket})
        relay(parent, pm, helper, cm)

      {:startup_authorized, ticket} ->
        send(helper, {:startup_authorized, ticket})
        relay(parent, pm, helper, cm)

      message ->
        send(helper, message)
        relay(parent, pm, helper, cm)
    end
  end

  def run(parent, group, id, spec) do
    parent_monitor = Process.monitor(parent)
    Process.monitor(spec.launcher)

    case Beamlet.Agent.start(spec.authority, Keyword.put(spec.options, :delegator, self())) do
      {:ok, child} ->
        send(spec.launcher, {:owned, child.pid})
        monitor = Process.monitor(child.pid)

        ticket = make_ref()
        send(spec.launcher, {:child_startup, self(), group, ticket})

        with :ok <- startup(ticket),
             {:ok, turn} <- Beamlet.Agent.input(child, spec.input),
             :ok <- Beamlet.Agent.subscribe(child) do
          send(parent, {:child_observed, group, id, child, turn})
          Process.send_after(self(), :expired, 60_000)
          await(parent, parent_monitor, monitor, group, id, child, turn)
        else
          _ -> finish(parent, group, id, child, nil, {:error, :child_start_failed})
        end

      _ ->
        send(parent, {:delegation_result, group, id, nil, nil, {:error, :authority_unavailable}})
    end
  end

  defp startup(ticket) do
    receive do
      :stop -> {:error, :stopped}
      {:DOWN, _, _, _, _} -> {:error, :owner_lost}
      {:startup_authorized, ^ticket} -> startup_clear()
    after
      5000 -> {:error, :startup_timeout}
    end
  end

  defp startup_clear do
    receive do
      :stop -> {:error, :stopped}
      {:DOWN, _, _, _, _} -> {:error, :owner_lost}
    after
      0 -> :ok
    end
  end

  defp await(parent, pm, cm, group, id, child, turn) do
    receive do
      {:beamlet_agent, ^child, seq, {:snapshot, snapshot}} ->
        # Credits are best-effort; the snapshot and monitors drive completion.
        _ = Beamlet.Agent.ack(child, seq)

        cond do
          snapshot.turn == turn and snapshot.status == :done ->
            finish(parent, group, id, child, turn, {:ok, snapshot.final})

          snapshot.status in [:error, :stopped] and
              (snapshot.turn == turn or snapshot.terminal_turn == turn) ->
            finish(parent, group, id, child, turn, {:error, snapshot.final || :child_stopped})

          true ->
            await(parent, pm, cm, group, id, child, turn)
        end

      {:DOWN, ^cm, _, _, _} ->
        send(parent, {:delegation_result, group, id, child, turn, {:error, :child_lost}})

      {:DOWN, ^pm, _, _, _} ->
        cleanup(child)

      {:DOWN, _, _, _, _} ->
        cleanup(child)

      :stop ->
        cleanup(child)

      :expired ->
        finish(parent, group, id, child, turn, {:error, :delegation_expired})
    end
  end

  defp finish(parent, group, id, child, turn, result) do
    # Cleanup cannot replace the already selected child result.
    _ = cleanup(child)
    send(parent, {:delegation_result, group, id, child, turn, result})
  end

  defp cleanup(child) do
    # Attempt every retirement step even when an earlier live reference has expired.
    _ = Beamlet.Agent.stop_turn(child)
    _ = Beamlet.Agent.unsubscribe(child)
    Beamlet.Agent.close(child)
  end
end
