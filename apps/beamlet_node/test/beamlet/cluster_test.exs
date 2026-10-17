defmodule Beamlet.Node.ClusterTest do
  use ExUnit.Case
  alias Beamlet.Node.Cluster

  test "authority is explicit and restricted to trusted deployment names" do
    assert {:ok, :authority@localhost} =
             Cluster.authority("authority@localhost", ["authority@localhost"])

    for {name, allowed} <- [
          {"other@localhost", []},
          {"invalid", ["invalid"]},
          {"a@host", ["a@host", :bad]},
          {"a@host", ["a@host" | :bad]},
          {"a@host", nil},
          {nil, []},
          {"a@host", ["a@host", <<255>>]},
          {"a@host\n", ["a@host\n"]},
          {"a@höst", ["a@höst"]}
        ] do
      assert {:error, :invalid_authority} = Cluster.authority(name, allowed)
      assert {:error, :invalid_authority} = Cluster.connect(name, allowed)
    end
  end

  test "whole allowlist and exact count/name byte boundaries are validated" do
    names = for i <- 1..32, do: "node#{i}@localhost"
    assert {:ok, _} = Cluster.authority(hd(names), names)
    assert {:error, :invalid_authority} = Cluster.authority(hd(names), names ++ ["extra@host"])
    at_limit = String.duplicate("a", 253) <> "@h"
    assert byte_size(at_limit) == 255
    assert {:ok, _} = Cluster.authority(at_limit, [at_limit])
    over_limit = "a" <> at_limit
    assert {:error, :invalid_authority} = Cluster.authority(over_limit, [over_limit])
  end

  test "rejected and merely allowlisted strings are not atomized" do
    fresh = "untrusted_#{System.unique_integer([:positive])}@localhost"
    assert_raise ArgumentError, fn -> String.to_existing_atom(fresh) end
    assert {:error, :invalid_authority} = Cluster.authority(fresh, [])
    assert {:ok, []} = Cluster.connected([fresh])
    assert_raise ArgumentError, fn -> String.to_existing_atom(fresh) end
  end

  test "connected nodes require a valid complete allowlist, with no implicit connect" do
    assert {:ok, []} = Cluster.connected([])
    assert {:error, :invalid_authority} = Cluster.connected(["bad"])
    assert {:error, :invalid_authority} = Cluster.connected(List.duplicate("a@host", 33))
    assert {:error, :invalid_authority} = Cluster.connected(["a@host" | :bad])
    assert {:error, :invalid_authority} = Cluster.connected(nil)
    assert {:error, :unavailable} = Cluster.connect("missing@localhost", ["missing@localhost"])
  end
end
