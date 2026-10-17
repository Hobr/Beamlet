defmodule Beamlet.Node.AgentsTest do
  use ExUnit.Case
  alias Beamlet.Node.Agents

  test "invalid target sets reject wholly, no atomization or connection" do
    for bad <- [
          nil,
          ["untrusted@host"],
          [node(), node()],
          List.duplicate(node(), 33),
          [nil],
          [node() | :bad]
        ] do
      assert {:error, :invalid_query} = Agents.discover(bad)
    end

    assert {:ok, %{agents: [], failures: %{}, complete: true}} = Agents.discover([])
    missing = :beamlet_discovery_missing@localhost

    assert {:ok, %{agents: [], failures: %{^missing => :unavailable}, complete: false}} =
             Agents.discover([missing])

    refute missing in Node.list(:connected)
  end

  test "whole envelope limit reserves all subsequent failure projections" do
    targets = for i <- 1..32, do: String.to_atom("node#{i}@" <> String.duplicate("h", 240))

    result =
      Enum.reduce(targets, %{agents: [], failures: %{}, complete: true}, fn target, acc ->
        agents =
          for i <- 1..128,
              do: %{authority: target, id: String.pad_leading("#{i}", 128, "x"), pid: self()}

        Agents.retain(acc, target, {:ok, agents})
      end)

    assert result.complete == false
    assert :limit in Map.values(result.failures)
    assert :erlang.external_size({:ok, result}) <= 1_048_576

    assert length(Enum.uniq(Enum.map(result.agents, & &1.authority))) + map_size(result.failures) ==
             32
  end

  test "32 explicit missing targets are classified without truncation" do
    targets = for i <- 1..32, do: String.to_atom("discovery_missing#{i}@localhost")
    assert {:ok, %{agents: [], failures: failures, complete: false}} = Agents.discover(targets)
    assert map_size(failures) == 32
    assert Enum.uniq(Map.values(failures)) == [:unavailable]
    assert {:error, :invalid_query} = Agents.discover([:extra@localhost | targets])
  end
end
