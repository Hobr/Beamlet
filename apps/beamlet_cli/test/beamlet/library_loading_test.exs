defmodule Beamlet.CLI.LibraryLoadingTest do
  use ExUnit.Case

  test "dependency loading and empty generated hosts do not compose roles or read stdin" do
    assert {:ok, _} = Application.ensure_all_started(:beamlet_node)
    assert Application.spec(:beamlet_node, :mod) == []
    assert {:ok, _} = Application.ensure_all_started(:beamlet_cli)
    assert Supervisor.which_children(Beamlet.CLI.Supervisor) == []

    for name <- [
          Beamlet.Node,
          Beamlet.Node.Routes,
          Beamlet.Node.Provider,
          Beamlet.Runtime.Directory,
          Beamlet.Runtime.ExecutorGateway,
          Beamlet.Agent.Registry
        ] do
      assert Process.whereis(name) == nil
    end
  end
end
