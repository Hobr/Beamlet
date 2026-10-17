defmodule Beamlet.Agent.OperationOwner do
  @moduledoc false
  alias Beamlet.Agent.Lifecycle

  def run(agent, token, operation, authority, dispatch \\ []) do
    Lifecycle.run(
      agent,
      fn controller -> submit(controller, token, operation, dispatch) end,
      authority,
      :operation
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
        Beamlet.Runtime.ack(ref, seq)
        await(ref)
    end
  end
end
