defmodule Beamlet.Storage.Artifacts do
  @moduledoc """
  Dataset-local artifact content. `put/2` and `verify_references/2` must run
  inside the caller's dataset transaction (e.g. Ecto.Multi.run), so references
  and content roll back together. No filesystem/object-store effects or GC.
  """
  alias Beamlet.Storage.{Codec, Transaction}
  alias Beamlet.Storage.Schema.Artifact

  def changeset(attrs) do
    Artifact.changeset(%Artifact{}, attrs)
    |> Ecto.Changeset.unique_constraint(:id, name: :artifacts_pkey)
    |> Ecto.Changeset.unique_constraint(:id)
    |> Ecto.Changeset.unique_constraint(:digest)
  end

  def put(repo, attrs) do
    cs = changeset(attrs)

    cond do
      not repo.in_transaction?() -> {:error, :invalid_data}
      not cs.valid? -> validation_error(cs)
      true -> insert(repo, cs)
    end
  end

  defp validation_error(cs) do
    if Enum.any?(cs.errors, fn {_, {message, _}} -> message == "limit" end),
      do: {:error, :limit},
      else: {:error, :invalid_data}
  end

  defp insert(repo, cs) do
    case repo.insert(cs, log: false) do
      {:ok, record} -> {:ok, record}
      {:error, _} -> {:error, :conflict}
    end
  end

  def fetch(repo, id) do
    if Codec.uuid?(id) do
      Transaction.read(fn -> do_fetch(repo, id) end)
    else
      {:error, :invalid_data}
    end
  end

  defp do_fetch(repo, id) do
    case repo.get(Artifact, id, log: false) do
      nil -> {:error, :artifact_missing}
      artifact -> validate_stored(artifact)
    end
  end

  defp validate_stored(artifact) do
    attrs = Map.from_struct(artifact) |> Map.delete(:__meta__)
    if changeset(attrs).valid?, do: {:ok, artifact}, else: {:error, :invalid_data}
  end

  def verify_references(repo, ids) when is_list(ids) and length(ids) <= 1024 do
    if repo.in_transaction?() do
      Enum.reduce_while(ids, :ok, fn id, :ok -> verify_reference(repo, id) end)
    else
      {:error, :invalid_data}
    end
  end

  def verify_references(_, ids) when length(ids) > 1024, do: {:error, :limit}
  def verify_references(_, _), do: {:error, :invalid_data}

  defp verify_reference(repo, id) do
    case fetch(repo, id) do
      {:ok, _} -> {:cont, :ok}
      error -> {:halt, error}
    end
  end
end
