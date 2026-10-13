defmodule BeamletRuntimeTest do
  use ExUnit.Case
  doctest BeamletRuntime

  test "greets the world" do
    assert BeamletRuntime.hello() == :world
  end
end
