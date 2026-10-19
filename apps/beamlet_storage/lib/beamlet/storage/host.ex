defmodule Beamlet.Storage.Host do
  @moduledoc """
  显式资源的生命周期所有者。datasets 中每项为 %{key: atom, repo: module, options: Dataset选项}，key 与 Repo 模块各自唯一。只打开已安装资源，不初始化、迁移或自动重开；只关闭自己成功打开的 Repo。handles 表示打开成功的句柄，status 才执行当前校验及回滚写探针。

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

  @typedoc "显式资源项；key 与 repo 在同一 Host 内分别唯一，options 含完整 descriptor。

An explicit resource; the host owns only Repos it successfully opens."
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
  @doc "启动显式资源宿主，传入 datasets 列表及可选 name。配置形状无效则拒绝启动；单个资源打开失败保留原因，宿主仍可启动。"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc "返回 {:ok, key到Repo的映射}，只含已成功打开且未观测到退出的资源；不代表当前可写，调用失败返回 storage_unavailable。"
  @spec handles(GenServer.server()) :: handles() | {:error, :storage_unavailable}
  def handles(name \\ __MODULE__), do: call(name, :handles)
  @doc "每次对成功打开资源执行格式校验和回滚写探针；打开失败资源保留原始安全原因。返回按 key 的状态映射或 storage_unavailable。"
  @spec status(GenServer.server()) :: statuses() | {:error, :storage_unavailable}
  def status(name \\ __MODULE__), do: call(name, :status)

  @spec call(GenServer.server(), :handles | :status) ::
          handles() | statuses() | {:error, :storage_unavailable}
  defp call(name, message) do
    GenServer.call(name, message, 5000)
  catch
    :exit, _ -> {:error, :storage_unavailable}
  end

  @doc "校验资源形状后逐项尝试打开，记录每项成功或失败；捕获链接退出以保留安全不可用状态。"
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

  @doc "返回已有打开句柄或每项当前探测结果；失败打开不会在调用时重试。"
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

  @doc "观测所拥有 Repo 的链接退出，将对应资源标记不可用，不自动重开。"
  @impl true
  @spec handle_info({:EXIT, pid(), term()}, state()) :: {:noreply, state()}
  def handle_info({:EXIT, pid, _reason}, state) do
    {:noreply,
     Map.new(state, fn
       {key, %{opened: {:ok, ^pid}} = d} -> {key, %{d | opened: {:error, :storage_unavailable}}}
       pair -> pair
     end)}
  end

  @doc "宿主正常终止回调只停止自己成功打开且仍存活的 Repo；失败打开未取得所有权。"
  @impl true
  @spec terminate(term(), state()) :: :ok
  def terminate(_, state) do
    Enum.each(state, fn
      {_, %{repo: repo, opened: {:ok, pid}}} -> if Process.alive?(pid), do: repo.stop()
      _ -> :ok
    end)
  end
end
