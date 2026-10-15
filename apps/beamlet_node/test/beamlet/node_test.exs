defmodule Beamlet.NodeTest do
  use ExUnit.Case
  doctest Beamlet.Node

  test "greets the world" do
    assert Beamlet.Node.hello() == :world
  end
end
