defmodule Beamlet.Web.Host do
  @moduledoc """
  启动时显式启用的 Web 宿主。角色须含 interaction，每 VM 一棵 Node；rest_for_one 按 Node、Presets、Handles、临时 Bootstrap 排列，Node 丢失会清空后续导航。

  Startup-only opt-in Web host. One Node tree per VM.
  """
  use Supervisor
  alias Beamlet.Harness.Model
  alias Beamlet.Node.Cluster
  alias Beamlet.Web.Presets

  @typedoc "通过启动验证的 Web 宿主策略，包含私有已解析目录；字符串节点名须经 Cluster 验证。

Validated Web startup policy with private resolved preset bindings."
  @type settings :: [
          {:enabled, boolean()}
          | {:node, Beamlet.Node.options()}
          | {:allowed_nodes, [binary()]}
          | {:peers, [binary()]}
          | {:catalogue, Presets.configuration()}
        ]
  @doc "验证启动配置并返回规范化值或静态配置错误；不启动角色、连接节点或调用提供方。"
  @spec configuration(term()) :: {:ok, settings()} | {:error, :invalid_web_host_configuration}
  def configuration(settings) do
    with true <- is_list(settings) and Keyword.keyword?(settings),
         true <-
           Keyword.keys(settings) -- [:enabled, :node, :allowed_nodes, :peers, :catalogue] == [],
         true <- Enum.uniq(Keyword.keys(settings)) == Keyword.keys(settings),
         enabled when is_boolean(enabled) <- Keyword.get(settings, :enabled, false),
         opts <- Keyword.get(settings, :node, roles: [:interaction]),
         true <- is_list(opts) and Keyword.keyword?(opts),
         true <- Enum.uniq(Keyword.keys(opts)) == Keyword.keys(opts),
         true <- :interaction in Keyword.get(opts, :roles, []),
         {:ok, _} <- Beamlet.Node.configuration(opts),
         allowed <- Keyword.get(settings, :allowed_nodes, []),
         {:ok, _} <- Cluster.connected(allowed),
         peers <- Keyword.get(settings, :peers, []),
         true <- is_list(peers) and length(peers) <= 32,
         true <- Enum.uniq(peers) == peers and Enum.all?(peers, &(&1 in allowed)),
         {:ok, catalogue} <-
           Presets.configuration(
             Keyword.get(settings, :catalogue, %{}),
             allowed,
             Keyword.get(opts, :model_providers, Model.default_providers())
           ) do
      {:ok,
       [enabled: enabled, node: opts, allowed_nodes: allowed, peers: peers, catalogue: catalogue]}
    else
      _ -> {:error, :invalid_web_host_configuration}
    end
  rescue
    _ -> {:error, :invalid_web_host_configuration}
  end

  @doc "由监督树启动本模块的具名进程；同一 VM 不应重复启动。"
  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(settings), do: Supervisor.start_link(__MODULE__, settings, name: __MODULE__)

  @impl true
  @spec init(term()) ::
          {:ok, {Supervisor.sup_flags(), [Supervisor.child_spec()]}}
          | {:stop, :invalid_web_host_configuration}
  def init(settings) do
    case configuration(settings) do
      {:ok, config} ->
        children =
          if config[:enabled],
            do: [
              {Beamlet.Node, config[:node]},
              {Beamlet.Web.Presets, config[:catalogue]},
              Beamlet.Web.Handles,
              {Beamlet.Web.Host.Bootstrap, config}
            ],
            else: []

        Supervisor.init(children, strategy: :rest_for_one)

      {:error, _} ->
        {:stop, :invalid_web_host_configuration}
    end
  end
end
