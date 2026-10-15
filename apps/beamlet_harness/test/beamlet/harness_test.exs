defmodule Beamlet.HarnessTest do
  use ExUnit.Case
  doctest Beamlet.Harness

  test "greets the world" do
    assert Beamlet.Harness.hello() == :world
  end
end
