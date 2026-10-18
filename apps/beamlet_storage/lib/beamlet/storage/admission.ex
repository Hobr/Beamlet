defmodule Beamlet.Storage.Admission do
  @moduledoc """
  Host-level durable admission for one explicitly described dataset, distinct from process/Repo
  readiness.

  Readiness keeps its current meaning (the required local registrations exist).
  Admission answers a different question: does this dataset pass the format and
  migration check *and* accept a real write right now. `status/1` performs that
  probe on every call, so a cached observation is never reported as admission.

  The host starts this process when it configures durable storage. `consult/1`
  is the gate durable submit/accept paths use; a VM without a started admission
  process has no host admission policy (library/embedding callers own it), which
  is reported as `:not_configured` and admits. `failure/2` turns admission off
  after a durable write path failed, and the next probe re-enables it only once
  the dataset really accepts a write again.
  """
  use GenServer
  alias Beamlet.Storage.{Codec, Dataset, Installation, Transaction}
  alias Ecto.Adapters.SQL

  # A real write to the durable file, rolled back inside the same transaction:
  # nothing is committed, but lock acquisition and the page/WAL write path are
  # exercised. A read-only or unreachable dataset cannot pass it. Because the probe
  # always rolls back, no commit and therefore no fsync happens here.
  @probe_sql "UPDATE storage_metadata SET format_version = format_version WHERE id = 1"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Fresh admission status: `:admitted | {:refused, reason} | :not_configured`
  (`:not_configured` means no admission process exists in this VM).
  """
  def status(name \\ __MODULE__) do
    case Process.whereis(name) do
      nil -> :not_configured
      _pid -> GenServer.call(name, :status, 5000)
    end
  catch
    :exit, _ -> {:refused, :storage_unavailable}
  end

  def admitted?(name \\ __MODULE__), do: status(name) == :admitted

  @doc """
  Durable submit/accept gate: `:ok`, or `{:error, :durable_not_admitted}` when a
  host admission process reports a refused dataset. Never consults a cached flag.
  """
  def consult(name \\ __MODULE__) do
    case checks(name) do
      :admitted -> :ok
      :not_configured -> :ok
      _refused -> {:error, :durable_not_admitted}
    end
  end

  # `:consult` honours a recorded failure without re-probing it away; `:status` is
  # the operator view and always probes.
  defp checks(name) do
    case Process.whereis(name) do
      nil -> :not_configured
      _pid -> GenServer.call(name, :consult, 5000)
    end
  catch
    :exit, _ -> {:refused, :storage_unavailable}
  end

  @doc "Turns admission off after a durable write path failed; `reason` is a safe atom."
  def failure(reason, name \\ __MODULE__) when is_atom(reason) do
    case Process.whereis(name) do
      # Synchronous: a caller that just lost a write must not race the next gate
      # check into an admitted answer.
      nil -> :ok
      pid -> GenServer.call(pid, {:failure, reason}, 5000)
    end
  catch
    :exit, _ -> :ok
  end

  @doc """
  One admission probe against a running dataset: the format/migration check of
  `Beamlet.Storage.Dataset.verify/2` plus a real rolled-back write.
  Returns `:admitted` or `{:error, reason}`.
  """
  def probe(repo, dataset_opts) do
    with :ok <- Dataset.verify(repo, dataset_opts),
         :ok <- write_probe(repo),
         do: :admitted
  end

  @impl true
  def init(opts) do
    with true <- Keyword.keyword?(opts),
         repo when is_atom(repo) and repo != nil <- Keyword.get(opts, :repo),
         dataset_id when is_binary(dataset_id) <- Keyword.get(opts, :dataset_id),
         true <- Codec.uuid?(dataset_id),
         :ok <- Installation.validate(Keyword.get(opts, :descriptor)),
         true <- is_nil(Keyword.get(opts, :reason)) or is_atom(Keyword.get(opts, :reason)) do
      {:ok,
       %{
         repo: repo,
         dataset_opts: Keyword.drop(opts, [:repo, :name, :reason, :resources]),
         reason: Keyword.get(opts, :reason),
         resources: Keyword.get(opts, :resources, []),
         # nil means "not evaluated yet": the first consult/status probes. Only a
         # recorded write failure short-circuits the probe.
         status: nil
       }}
    else
      _ -> {:stop, :invalid_admission_configuration}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = probe(state)
    # A probe that succeeded clears a previously recorded failure; a probe that
    # failed replaces it. Either way the caller sees the state that was just probed.
    {:reply, status, %{state | status: status}}
  end

  # A caller that just saw a durable write fail can bypass the probe once, so the
  # next submit is refused even if the probe would succeed.
  # A caller that lost a write records the failure synchronously, so the next gate
  # check cannot race into an admitted answer.
  def handle_call({:failure, reason}, _from, state),
    do: {:reply, :ok, %{state | status: {:refused, reason}}}

  def handle_call(:consult, _from, state) do
    status =
      case state.status do
        {:refused, _} = refused -> refused
        _ -> probe(state)
      end

    {:reply, status, state}
  end

  @impl true
  def handle_cast({:failure, reason}, state),
    do: {:noreply, %{state | status: {:refused, reason}}}

  # A dataset that never opened keeps the operator-visible reason (`:dataset_missing`,
  # `:restored_backup`, `:schema_unsupported`, ...) instead of a generic outage. A
  # recorded write failure is honoured by `:consult` before this probe runs, so a
  # failed write path is never admitted merely because a later read happens to work.
  defp probe(state) do
    if state.reason != nil do
      {:refused, state.reason}
    else
      case probe_resources([{state.repo, state.dataset_opts} | state.resources]) do
        :admitted -> :admitted
        {:error, reason} -> {:refused, reason}
      end
    end
  end

  defp probe_resources(resources) do
    Enum.reduce_while(resources, :admitted, fn {repo, opts}, :admitted ->
      case probe(repo, opts) do
        :admitted -> {:cont, :admitted}
        error -> {:halt, error}
      end
    end)
  end

  defp write_probe(repo) do
    case Transaction.write(repo, fn -> rollback_probe(repo) end) do
      {:error, :probe_executed} -> :ok
      {:error, :probe_refused} -> {:error, :write_failed}
      _other -> {:error, :storage_unavailable}
    end
  rescue
    _ -> {:error, :storage_unavailable}
  catch
    :exit, _ -> {:error, :storage_unavailable}
  end

  defp rollback_probe(repo) do
    case SQL.query(repo, @probe_sql, [], log: false) do
      {:ok, _result} -> repo.rollback(:probe_executed)
      _error -> repo.rollback(:probe_refused)
    end
  end
end
