defmodule Beamlet.Storage.References do
  @moduledoc "Dataset-local artifact reference verification for persisted JSON envelopes."
  alias Beamlet.Storage.Artifacts

  @doc "Collect artifact identities from a bounded JSON envelope."
  def ids(value), do: collect(value)

  def verify(repo, value) do
    with {:ok, ids} <- collect(value), do: Artifacts.verify_references(repo, Enum.uniq(ids))
  end

  @doc "Verify immutable dataset content during read-only reconstruction, without a write transaction."
  def verify_read(repo, value) do
    with {:ok, ids} <- collect(value) do
      verify_read_ids(repo, Enum.uniq(ids))
    end
  end

  defp verify_read_ids(repo, ids) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case Artifacts.fetch(repo, id) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp collect(map) when is_map(map) do
    Enum.reduce_while(map, {:ok, []}, fn {key, value}, {:ok, acc} ->
      case field(key, value) do
        {:ok, ids} -> {:cont, {:ok, ids ++ acc}}
        error -> {:halt, error}
      end
    end)
  end

  defp collect(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acc} ->
      case collect(value) do
        {:ok, ids} -> {:cont, {:ok, ids ++ acc}}
        error -> {:halt, error}
      end
    end)
  end

  defp collect(_), do: {:ok, []}
  defp field("artifact_id", value), do: {:ok, [value]}

  defp field(key, value) when key in ~w(artifact_ids artifact_refs) and is_list(value),
    do: {:ok, value}

  defp field(key, _) when key in ~w(artifact_ids artifact_refs), do: {:error, :invalid_data}
  defp field(_, value), do: collect(value)
end
