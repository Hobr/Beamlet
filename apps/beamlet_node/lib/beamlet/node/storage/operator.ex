defmodule Beamlet.Node.Storage.Operator do
  @moduledoc """
  Explicit operator actions for a durable dataset. Installing/migrating is never
  done by an Agent, by host boot or by `Beamlet.Storage.Dataset.open/2`: this
  module is invoked deliberately, once, by a trusted operator command.

  Each dataset is installed exactly once. An already-installed dataset is refused
  (`:dataset_exists`), a missing journal path or invalid configuration is refused
  before any file is created, and a failed installation is never retried as a new
  dataset. The Repo started for the installation is stopped again afterwards, so
  no application is left running by the command.
  """
  alias Beamlet.Storage.Dataset

  alias Beamlet.Actions.Storage.ExecutorJournalRepo
  alias Beamlet.Agent.Storage.PostgresAuthorityRepo
  alias Beamlet.Agent.Storage.SQLiteAuthorityRepo
  alias Beamlet.Node.Storage, as: Host

  @doc """
  Installs the datasets `roles` need from a trusted `:storage` block (same shape
  as `Beamlet.Node.Storage.configuration/2`).

  Returns `{:ok, %{authority: :installed | nil, journal: :installed | nil}}` or
  `{:error, {:authority | :journal, reason}}` / `{:error,
  :invalid_storage_configuration}`.
  """
  def initialize(roles, storage) do
    with {:ok, %{adapter: adapter, authority: authority, journal: journal}} <-
           Host.datasets(roles, storage) do
      with {:ok, authority} <- install(:authority, authority_repo(adapter), authority),
           {:ok, journal} <- install(:journal, ExecutorJournalRepo, journal) do
        {:ok, %{authority: authority, journal: journal}}
      end
    end
  end

  defp install(_role, _repo, nil), do: {:ok, nil}

  defp install(role, repo, opts) do
    case Dataset.initialize(repo, opts) do
      {:ok, _pid} ->
        stop(repo)
        {:ok, :installed}

      {:error, reason} ->
        # Dataset.initialize removes the Repo it started; a Repo that was already
        # running belongs to its host and is left alone.
        {:error, {role, reason}}
    end
  end

  defp stop(repo) do
    if Process.whereis(repo), do: repo.stop(5000)
    :ok
  catch
    _, _ -> :ok
  end

  defp authority_repo(:postgres), do: PostgresAuthorityRepo
  defp authority_repo(:sqlite), do: SQLiteAuthorityRepo
end
