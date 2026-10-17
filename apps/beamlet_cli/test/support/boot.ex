defmodule Beamlet.CLI.TestBoot do
  @moduledoc false
  alias Beamlet.Runtime.Directory

  def boot(opts) do
    {:ok, _} = Application.ensure_all_started(:beamlet_node)
    {:ok, pid} = Beamlet.Node.start_link(opts)
    Process.unlink(pid)
    :ok
  end

  def capacity_fence(n \\ 100) do
    if map_size(:sys.get_state(Beamlet.Runtime.ExecutorGateway).tasks) == 0 do
      System.monotonic_time(:millisecond)
    else
      if n == 0, do: raise("gateway capacity timeout")
      Process.sleep(10)
      capacity_fence(n - 1)
    end
  end

  def fresh_capacity(executor, fence, n \\ 100) do
    if Enum.any?(Directory.snapshots(), fn {_, r} ->
         r.node == executor and r.lease > fence and r.available["native"] == 2
       end) do
      :ok
    else
      if n == 0, do: raise("fresh capacity report timeout")
      Process.sleep(10)
      fresh_capacity(executor, fence, n - 1)
    end
  end

  defp ready?(capability) do
    Enum.any?(Directory.snapshots(), fn {_, report} -> capability in report.capabilities end)
  catch
    :exit, _ -> false
  end

  def barrier(capability, n \\ 400) do
    if ready?(capability) do
      :ok
    else
      if n == 0, do: raise("discovery timeout")

      receive do
      after
        10 -> barrier(capability, n - 1)
      end
    end
  end
end
