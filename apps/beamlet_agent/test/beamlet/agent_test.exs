defmodule Beamlet.AgentTest do
  use ExUnit.Case
  alias Beamlet.Agent

  setup do
    start_supervised!(Beamlet.Agent.AuthoritySupervisor)
    :ok
  end

  test "authority Agent capacity rejects explicitly" do
    for i <- 1..128 do
      assert {:ok, _} =
               Agent.start(node(), id: "capacity#{i}", model: %{id: "m", capability: "m"})
    end

    assert {:error, :max_children} =
             Agent.start(node(), id: "overflow", model: %{id: "m", capability: "m"})
  end

  test "authority identity is unique and subscription is snapshot first" do
    opts = [id: "one", model: %{id: "model", capability: "model"}]
    assert {:ok, ref} = Agent.start(node(), opts)
    assert {:error, _} = Agent.start(node(), opts)
    assert :ok = Agent.subscribe(ref)
    assert_receive {:beamlet_agent, ^ref, sequence, {:snapshot, %{status: :idle}}}
    assert :ok = Agent.ack(ref, sequence)
    assert :ok = Agent.stop_turn(ref)
    assert_receive {:beamlet_agent, ^ref, _, {:snapshot, %{status: :stopped}}}
    assert {:error, :stale_ref} = Agent.snapshot(%{ref | incarnation: make_ref()})
  end

  test "oversize executable input is rejected and context remains untouched" do
    {:ok, ref} = Agent.start(node(), id: "large", model: %{id: "m", capability: "m"})
    assert {:error, :invalid_or_oversize_input} = Agent.input(ref, String.duplicate("a", 65_537))
    assert {:ok, %{status: :idle, turn: nil}} = Agent.snapshot(ref)
  end

  test "subscriber limit and removal are explicit" do
    {:ok, ref} = Agent.start(node(), id: "subs", model: %{id: "m", capability: "m"})

    sinks =
      for _ <- 1..32,
          do:
            spawn(fn ->
              receive do
                :stop -> :ok
              end
            end)

    on_exit(fn -> Enum.each(sinks, &Process.exit(&1, :kill)) end)
    Enum.each(sinks, fn sink -> assert :ok = Agent.subscribe(ref, sink) end)
    assert {:error, :subscriber_limit} = Agent.subscribe(ref)
    assert :ok = Agent.unsubscribe(ref, hd(sinks))
    assert :ok = Agent.subscribe(ref)
  end
end
