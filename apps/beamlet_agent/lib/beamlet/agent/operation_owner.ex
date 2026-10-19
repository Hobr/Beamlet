defmodule Beamlet.Agent.OperationOwner do
  @spec run(pid(), reference(), Beamlet.Actions.Operation.t(), pid(), keyword()) :: :ok
  @spec submit(pid(), reference(), Beamlet.Actions.Operation.t(), keyword()) ::
          {:operation_failed, reference(), {:error, atom()}}
  @spec await(Beamlet.Actions.OperationRef.t()) :: no_return()
  @moduledoc false
  # 阻塞 submit/ack 位于 Lifecycle 的 linked worker，控制器可在基础设施挂起时独立响应所有权丢失。
  alias Beamlet.Agent.Lifecycle

  def run(agent, token, operation, authority, dispatch \\ []) do
    {identity, dispatch} = Keyword.pop(dispatch, :agent_identity)

    Lifecycle.run(
      agent,
      fn controller -> submit(controller, token, operation, dispatch) end,
      authority,
      :operation,
      identity
    )
  end

  defp submit(controller, token, operation, dispatch) do
    opts =
      Keyword.merge(
        [owner: controller, sink: controller, require_live_owner: true],
        dispatch
      )

    case Beamlet.Runtime.submit(operation, opts) do
      {:ok, ref} ->
        send(controller, {:operation_ready, token, ref})
        await(ref)

      error ->
        send(controller, {:operation_failed, token, error})
    end
  end

  defp await(ref) do
    receive do
      {:ack, seq} ->
        # Credit acknowledgement is best-effort against a possibly expired Ref.
        _ = Beamlet.Runtime.ack(ref, seq)
        await(ref)
    end
  end
end
