defmodule Beamlet.ClientTest do
  use ExUnit.Case
  doctest Beamlet.Client

  test "greets the world" do
    assert Beamlet.Client.hello() == :world
  end
end
