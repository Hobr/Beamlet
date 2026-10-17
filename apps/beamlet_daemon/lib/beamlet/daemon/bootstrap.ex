defmodule Beamlet.Daemon.Bootstrap do
  @moduledoc false
  use Task, restart: :temporary
  alias Beamlet.Node.Cluster
  require Logger

  # Task.start_link acknowledges startup before running network work. The task is
  # owned by the host; Cluster owns and bounds each attempt, including caller loss.
  def start_link(settings), do: Task.start_link(__MODULE__, :run, [settings])

  def run(settings) do
    settings[:peers]
    |> Enum.with_index(1)
    |> Enum.each(fn {peer, index} ->
      case Cluster.connect(peer, settings[:allowed_nodes]) do
        :ok -> Logger.info("daemon startup peer #{index}: connected")
        {:error, _} -> Logger.warning("daemon startup peer #{index}: unavailable")
      end
    end)
  end
end
