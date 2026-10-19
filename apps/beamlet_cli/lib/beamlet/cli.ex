defmodule Beamlet.CLI do
  @moduledoc """
  显式启用的交互宿主。普通应用加载不启动 Node 或终端读取；配置只接受 enabled 与 allowed_nodes。

  Opt-in interaction host. No stdin or Node startup on ordinary loading.
  """
  alias Beamlet.Node.Cluster

  @typedoc "通过启动验证的宿主策略；字符串节点名须经 Cluster 验证。

Validated opt-in interaction host settings."
  @type settings :: [{:enabled, boolean()} | {:allowed_nodes, [binary()]}]
  @doc "验证启动配置并返回规范化值或静态配置错误；不启动角色、连接节点或调用提供方。"
  @spec configuration(term()) :: {:ok, settings()} | {:error, :invalid_configuration}
  def configuration(settings) do
    with true <- is_list(settings) and Keyword.keyword?(settings),
         keys = Keyword.keys(settings),
         true <- keys -- [:enabled, :allowed_nodes] == [] and keys == Enum.uniq(keys),
         enabled = Keyword.get(settings, :enabled, false),
         true <- is_boolean(enabled),
         allowed = Keyword.get(settings, :allowed_nodes, []),
         {:ok, _} <- Cluster.connected(allowed) do
      {:ok, [enabled: enabled, allowed_nodes: allowed]}
    else
      _ -> {:error, :invalid_configuration}
    end
  end
end
