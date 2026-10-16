defmodule Beamlet.Harness.Models.Deterministic do
  @moduledoc "Deterministic native model for integration fixtures; no external calls."
  @behaviour Beamlet.Harness.Model
  alias Beamlet.Harness.Context
  alias Beamlet.Harness.Models.OpenAICompatible
  @impl true
  def complete(request, %{reply: reply} = settings, context) do
    with false <- Context.cancelled?(context),
         true <- Map.keys(settings) == [:reply],
         :ok <- OpenAICompatible.validate_request(request) do
      Context.emit(context, %{phase: "complete"})
      OpenAICompatible.normalize(reply, request.catalogue)
    else
      true -> {:error, :cancelled}
      false -> {:error, :invalid_profile}
      error -> error
    end
  end

  def complete(_, _, _), do: {:error, :invalid_profile}
end
