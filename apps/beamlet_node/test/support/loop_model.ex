defmodule Beamlet.Node.TestLoopModel do
  @moduledoc false
  @behaviour Beamlet.Harness.Model
  alias Beamlet.Harness.Models.OpenAICompatible

  def complete(request, _settings, _context) do
    call = %{
      "id" => "loop",
      "type" => "function",
      "function" => %{"name" => "echo", "arguments" => "{\"text\":\"again\"}"}
    }

    assistant = %{"role" => "assistant", "content" => nil, "tool_calls" => [call]}

    with :ok <- OpenAICompatible.validate_request(request) do
      OpenAICompatible.normalize(
        %{"choices" => [%{"finish_reason" => "tool_calls", "message" => assistant}]},
        request.catalogue
      )
    end
  end
end
