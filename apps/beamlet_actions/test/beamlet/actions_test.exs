defmodule Beamlet.ActionsTest do
  use ExUnit.Case
  doctest Beamlet.Actions

  test "greets the world" do
    assert Beamlet.Actions.hello() == :world
  end
end
