defmodule Beamlet.AgentTest do
  use ExUnit.Case
  doctest Beamlet.Agent

  test "greets the world" do
    assert Beamlet.Agent.hello() == :world
  end
end
