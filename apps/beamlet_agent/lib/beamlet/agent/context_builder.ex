defmodule Beamlet.Agent.ContextBuilder do
  @moduledoc "Loads and verifies context sources before applying the pure conversation policy."
  alias Beamlet.Agent.Core.Context
  alias Beamlet.Agent.Loader
  alias Beamlet.Storage.{Codec, History, Inheritance, OperationRecords}

  defdelegate complete_boundary(messages), to: Context
  defdelegate observation(result, resolution), to: Context
  defdelegate reply(value), to: Context

  def build(repo, control, catalogue) do
    with true <- length(control["timeline"]) <= 128,
         {:ok, acc} <- load(repo, control) do
      Context.finish(acc, catalogue)
    else
      false -> {:error, :context_limit}
      error -> error
    end
  end

  def materialize(repo, control) do
    with {:ok, acc} <- load(repo, control), do: Context.messages(acc)
  end

  defp load(repo, control) do
    with {:ok, acc} <- Context.start(control) do
      Enum.reduce_while(control["timeline"], {:ok, acc}, &load_next(repo, control, &1, &2))
    end
  end

  defp load_next(repo, control, source, {:ok, current}) do
    with {:ok, entry} <- material(repo, control, source),
         {:ok, next} <- Context.append(current, entry) do
      {:cont, {:ok, next}}
    else
      error -> {:halt, error}
    end
  end

  defp material(repo, _control, %{"type" => "inherited_input"} = ref) do
    with {:ok, payload} <- Inheritance.input(repo, ref),
         do: {:ok, %{"source" => ref, "input" => payload}}
  end

  defp material(repo, _control, %{"type" => "inherited_result"} = ref) do
    with {:ok, %{"operation" => op}} <-
           OperationRecords.fetch(repo, ref["reference"]["operation_id"]),
         :ok <- Inheritance.operation(repo, op, ref["reference"]) do
      {:ok, %{"source" => ref, "operation" => op, "resolution" => ref["resolution"]}}
    end
  end

  defp material(repo, control, %{"type" => "input"} = ref) do
    with {:ok, e} <- History.event(repo, control["agent_id"], ref["seq"]),
         true <- e["id"] == ref["event_id"] and e["type"] == "input.accepted",
         {:ok, digest} <- Codec.digest(e["payload"], :event),
         true <- digest == ref["digest"] do
      {:ok, %{"source" => ref, "input" => e["payload"]}}
    else
      _ -> {:error, :invalid_reference}
    end
  end

  defp material(repo, control, %{"type" => "accepted_result", "reference" => ref} = source) do
    with {:ok, %{"operation" => op}} <- Loader.operation(repo, control["agent_id"], ref) do
      {:ok,
       %{"source" => source, "operation" => op, "resolution" => control["resolutions"][op["id"]]}}
    end
  end
end
