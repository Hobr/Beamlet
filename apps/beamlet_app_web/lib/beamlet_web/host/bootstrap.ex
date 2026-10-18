defmodule Beamlet.Web.Host.Bootstrap do
  @moduledoc false
  use Task, restart: :temporary
  require Logger
  alias Beamlet.Node.Cluster
  def start_link(config), do: Task.start_link(__MODULE__, :run, [config])

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
