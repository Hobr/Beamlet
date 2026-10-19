defmodule Beamlet.Server.Bootstrap do
  @moduledoc false
  # 临时任务在监督启动确认后逐个连接一次；失败继续本地服务，宿主消失时清理连接调用者，不重试。
  use Task, restart: :temporary
  alias Beamlet.Node.Cluster
  require Logger

  # Task.start_link acknowledges startup before running network work. The task is
  # owned by the host; Cluster owns and bounds each attempt, including caller loss.
  @spec start_link(Beamlet.Server.settings()) :: {:ok, pid()} | {:error, term()}
  def start_link(settings), do: Task.start_link(__MODULE__, :run, [settings])

  @spec run(Beamlet.Server.settings()) :: :ok
  def run(settings) do
    settings[:peers]
    |> Enum.with_index(1)
    |> Enum.each(fn {peer, index} ->
      case Cluster.connect(peer, settings[:allowed_nodes]) do
        :ok -> Logger.info("server startup peer #{index}: connected")
        {:error, _} -> Logger.warning("server startup peer #{index}: unavailable")
      end
    end)
  end
end
