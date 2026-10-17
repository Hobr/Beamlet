defmodule Beamlet.DaemonTest do
  use ExUnit.Case
  doctest Beamlet.Daemon

  test "greets the world" do
    assert Beamlet.Daemon.hello() == :world
  end
end
