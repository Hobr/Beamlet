defmodule Beamlet.TUITest do
  use ExUnit.Case
  doctest Beamlet.TUI

  test "greets the world" do
    assert Beamlet.TUI.hello() == :world
  end
end
