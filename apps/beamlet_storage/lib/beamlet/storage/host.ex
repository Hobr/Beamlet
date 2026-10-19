defmodule Beamlet.Storage.Host do
  @moduledoc """
  Explicit lifecycle owner for named generic resources. Start with
  `datasets: [%{key: atom, repo: trusted_repo_module, options: dataset_options}]`.
  Options are the exact explicit Dataset options including the descriptor.
  Repo modules and keys must be distinct; instance registration is the Repo module.
  No domain wiring, initialization, migration, retry or automatic reopening occurs.
  `handles/1` returns ready key -> Repo handles. `status/1` freshly probes each
  dataset, including a rolled-back write; a failed open retains its safe reason.
  """
  use GenServer
  alias Beamlet.Storage.{Admission, Dataset, Installation}

  @typedoc "An explicit resource; the host owns only Repos it successfully opens."
  @type resource :: %{key: atom(), repo: module(), options: Dataset.options()}
  @typep opened_resource :: %{
           key: atom(),
           repo: module(),
           options: Dataset.options(),
           opened: {:ok, pid()} | {:error, Dataset.error()}
         }
  @typep state :: %{optional(atom()) => opened_resource()}
  @typep handles :: {:ok, %{optional(atom()) => module()}}
  @typep statuses :: %{optional(atom()) => :admitted | {:error, atom()}}
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @spec handles(GenServer.server()) :: handles() | {:error, :storage_unavailable}
  def handles(name \\ __MODULE__), do: call(name, :handles)
  @spec status(GenServer.server()) :: statuses() | {:error, :storage_unavailable}
  def status(name \\ __MODULE__), do: call(name, :status)

  @spec call(GenServer.server(), :handles | :status) ::
          handles() | statuses() | {:error, :storage_unavailable}
  defp call(name, message) do
    GenServer.call(name, message, 5000)
  catch
    :exit, _ -> {:error, :storage_unavailable}
  end

  @impl true
  @spec init(keyword()) :: {:ok, state()} | {:stop, :invalid_storage_configuration}
  def init(opts) do
    Process.flag(:trap_exit, true)
    datasets = Keyword.get(opts, :datasets)

    if valid?(datasets) do
      resources =
        Map.new(datasets, fn d ->
          {d.key, Map.put(d, :opened, Dataset.open(d.repo, d.options))}
        end)

      {:ok, resources}
    else
      {:stop, :invalid_storage_configuration}
    end
  end

  @spec valid?(term()) :: boolean()
  defp valid?(datasets) when is_list(datasets) do
    Enum.all?(datasets, fn
      %{key: key, repo: repo, options: options} = d ->
        map_size(d) == 3 and is_atom(key) and is_atom(repo) and Keyword.keyword?(options) and
          Installation.validate(options[:descriptor]) == :ok

      _ ->
        false
    end) and Enum.uniq_by(datasets, & &1.key) == datasets and
      Enum.uniq_by(datasets, & &1.repo) == datasets
  end

  defp valid?(_), do: false

  @impl true
  @spec handle_call(:handles | :status, GenServer.from(), state()) ::
          {:reply, handles() | statuses(), state()}
  def handle_call(:handles, _, state) do
    handles = for {key, %{repo: repo, opened: {:ok, _}}} <- state, into: %{}, do: {key, repo}
    {:reply, {:ok, handles}, state}
  end

  def handle_call(:status, _, state) do
    statuses =
      Map.new(state, fn {key, d} ->
        status =
          case d.opened do
            {:ok, _} -> Admission.probe(d.repo, d.options)
            {:error, reason} -> {:error, reason}
          end

        {key, status}
      end)

    {:reply, statuses, state}
  end

  @impl true
  @spec handle_info({:EXIT, pid(), term()}, state()) :: {:noreply, state()}
  def handle_info({:EXIT, pid, _reason}, state) do
    {:noreply,
     Map.new(state, fn
       {key, %{opened: {:ok, ^pid}} = d} -> {key, %{d | opened: {:error, :storage_unavailable}}}
       pair -> pair
     end)}
  end

  @impl true
  @spec terminate(term(), state()) :: :ok
  def terminate(_, state) do
    Enum.each(state, fn
      {_, %{repo: repo, opened: {:ok, pid}}} -> if Process.alive?(pid), do: repo.stop()
      _ -> :ok
    end)
  end
end
