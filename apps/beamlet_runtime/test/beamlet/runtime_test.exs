defmodule Beamlet.RuntimeTest do
  use ExUnit.Case
  doctest Beamlet.Runtime

  test "greets the world" do
    assert Beamlet.Runtime.hello() == :world
  end
end
