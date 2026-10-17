defmodule Beamlet.Node.TestLoopModel do
  alias Beamlet.Harness.Model
  @moduledoc false
  @behaviour Beamlet.Harness.Model
  def validate_invocation(_), do: :ok

  def complete(request, _, _) do
    with :ok <- Model.validate_request(request) do
      {:ok,
       %{
         kind: :tool_calls,
         content: nil,
         calls: [%{id: "loop", name: "echo", arguments: %{"text" => "again"}}]
       }}
    end
  end
end
