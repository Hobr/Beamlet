defmodule Beamlet.Web.Host.Bootstrap do
  @moduledoc false
  # 仅启动时对受信 peers 顺序连接一次；任务归宿主拥有，浏览器事件没有连接路径。
  use Task, restart: :temporary
  require Logger
  alias Beamlet.Node.Cluster
  @spec start_link(Beamlet.Web.Host.settings()) :: {:ok, pid()} | {:error, term()}
  def start_link(config), do: Task.start_link(__MODULE__, :run, [config])

  @spec run(Beamlet.Web.Host.settings()) :: :ok
  def run(config) do
    config[:peers]
    |> Enum.with_index(1)
    |> Enum.each(fn {peer, index} ->
      case Cluster.connect(peer, config[:allowed_nodes]) do
        :ok -> Logger.info("web startup peer #{index}: connected")
        _ -> Logger.warning("web startup peer #{index}: unavailable")
      end
    end)
  end
end
