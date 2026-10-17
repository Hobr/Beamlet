defmodule Beamlet.Web.HostPeer do
  @moduledoc false
  def boot do
    {:ok, _} = Application.ensure_all_started(:beamlet_node)
    {:ok, pid} = Beamlet.Node.start_link(roles: [:authority, :executor], limits: [refresh_ms: 20])
    Process.unlink(pid)
    :ok
  end
end
