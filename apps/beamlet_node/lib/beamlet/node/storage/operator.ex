defmodule Beamlet.Node.Storage.Operator do
  @moduledoc """
  可信运维者显式安装角色所需数据集。已有数据集拒绝，不覆盖或自动升级；成功后停止自己启动的 Repo，不停止宿主已有资源。多数据集顺序安装并非跨库原子事务。

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
  顺序安装角色需要的数据集；返回各角色 installed/nil 或带角色错误，不覆盖已有数据，不自动重试。

  Installs the datasets `roles` need from a trusted `:storage` block (same shape
  as `Beamlet.Node.Storage.configuration/2`).

  Returns `{:ok, %{authority: :installed | nil, journal: :installed | nil}}` or
  `{:error, {:authority | :journal, reason}}` / `{:error,
  :invalid_storage_configuration}`.
  """
  @spec initialize(term(), term()) ::
          {:ok, %{authority: :installed | nil, journal: :installed | nil}}
          | {:error, :invalid_storage_configuration | {:authority | :journal, atom()}}
  def initialize(roles, storage) do
    with {:ok, %{adapter: adapter, authority: authority, journal: journal}} <-
           Host.datasets(roles, storage) do
      with {:ok, authority} <- install(:authority, authority_repo(adapter), authority),
           {:ok, journal} <- install(:journal, ExecutorJournalRepo, journal) do
        {:ok, %{authority: authority, journal: journal}}
      end
    end
  end

  @spec install(:authority | :journal, module(), keyword() | nil) ::
          {:ok, :installed | nil} | {:error, {:authority | :journal, atom()}}
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

  @spec stop(module()) :: :ok
  defp stop(repo) do
    if Process.whereis(repo), do: repo.stop(5000)
    :ok
  catch
    _, _ -> :ok
  end

  @spec authority_repo(:postgres | :sqlite) :: module()
  defp authority_repo(:postgres), do: PostgresAuthorityRepo
  defp authority_repo(:sqlite), do: SQLiteAuthorityRepo
end
