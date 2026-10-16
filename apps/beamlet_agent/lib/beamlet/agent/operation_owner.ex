defmodule Beamlet.Agent.OperationOwner do
  @moduledoc false
  alias Beamlet.Agent.Lifecycle

  def run(agent, token, operation, authority) do
    Lifecycle.run(
      agent,
      fn controller -> submit(controller, token, operation) end,
      authority,
      :operation
    )
  end

  defp submit(controller, token, operation) do
    case Beamlet.Runtime.submit(operation,
           owner: controller,
           sink: controller,
           require_live_owner: true
         ) do
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
