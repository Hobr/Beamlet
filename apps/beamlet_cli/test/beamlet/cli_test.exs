defmodule Beamlet.CLITest do
  use ExUnit.Case

  test "ordinary CLI application has no terminal or Node child" do
    assert Supervisor.which_children(Beamlet.CLI.Supervisor) == []
    assert Process.whereis(Beamlet.Node) == nil
  end
end
