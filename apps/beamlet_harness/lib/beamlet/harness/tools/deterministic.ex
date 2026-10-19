defmodule Beamlet.Harness.Tools.Deterministic do
  @moduledoc "Deterministic native fixture Tool with local progress and cancellation hooks."
  @behaviour Beamlet.Harness.Tool
  alias Beamlet.Harness.{Arguments, Context}
  @impl true
  @spec descriptor() :: Beamlet.Harness.Catalogue.descriptor()
  def descriptor do
    %{
      "name" => "echo",
      "description" => "Return bounded fixture text",
      "parameters" => %{
        "type" => "object",
        "properties" => %{"text" => %{"type" => "string", "maxLength" => 1024}},
        "required" => ["text"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  @spec invoke(term(), term(), Context.t()) ::
          {:ok, %{text: String.t()}} | {:error, :cancelled | :invalid_arguments}
  def invoke(arguments, _settings, context \\ %Context{}) do
    with false <- Context.cancelled?(context),
         :ok <- Arguments.validate(arguments, descriptor()["parameters"]) do
      Context.emit(context, %{phase: "echo"})
      {:ok, %{text: arguments["text"]}}
    else
      true -> {:error, :cancelled}
      error -> error
    end
  end
end
