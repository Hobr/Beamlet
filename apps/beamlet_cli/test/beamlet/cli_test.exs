defmodule Beamlet.CLITest do
  use ExUnit.Case
  doctest Beamlet.CLI

  test "greets the world" do
    assert Beamlet.CLI.hello() == :world
  end
end
