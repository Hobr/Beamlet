defmodule Beamlet.NodeLifecycleTest do
  use ExUnit.Case
  alias Beamlet.Agent
  alias Beamlet.Harness.{Catalogue, Context}
  alias Beamlet.Harness.Tools.Deterministic
  alias Beamlet.Node.TestBinding
  alias Beamlet.Node.TestBoot
  alias Beamlet.Node.TestTool

  setup do
    profiles = %{
      "echo" => %{
        type: :tool,
        module: Beamlet.Harness.Tools.Deterministic,
        settings: %{},
        capability: "echo"
      },
      "tool" => %{
        type: :tool,
        module: TestTool,
        settings: %{observer: self()},
        capability: "tool"
      }
    }

    start_supervised!(
      {Beamlet.Node,
       roles: [:authority, :executor],
       profiles: profiles,
       model_providers: %{
         "loop" => Beamlet.Node.TestLoopModel,
         "held" => Beamlet.Node.TestModel,
         "plain" => Beamlet.Node.TestModel,
         "bad" => Beamlet.Node.TestModel
       },
       allowlist: %{
         model: [Beamlet.Node.TestModel, Beamlet.Node.TestLoopModel],
         tool: [TestTool, Beamlet.Harness.Tools.Deterministic]
       },
       pools: %{"native" => 8},
       limits: [refresh_ms: 20, expiry_ms: 500]}
    )

    TestBoot.barrier("model.provider:held")
    :ok
  end

  defp agent(id, profile \\ "plain") do
    {:ok, ref} = Agent.start(node(), id: id, model: TestBinding.binding(profile))
    ref
  end

  test "context reaches its bound without evicting messages" do
    ref = agent("context")
    Agent.subscribe(ref)

    for _ <- 1..64 do
      assert {:ok, _} = Agent.input(ref, "next")
      await_done(ref)
    end

    assert length(:sys.get_state(ref.pid).messages) == 128
    assert {:error, :invalid_or_oversize_input} = Agent.input(ref, "overflow")
    assert length(:sys.get_state(ref.pid).messages) == 128
  end

  defp await_error(ref) do
    receive do
      {:beamlet_agent, ^ref, seq, {:snapshot, snapshot}} ->
        Agent.ack(ref, seq)
        if snapshot.status == :error, do: snapshot, else: await_error(ref)
    after
      3000 -> flunk("error snapshot timeout")
    end
  end

  defp await_done(ref) do
    receive do
      {:beamlet_agent, ^ref, seq, {:snapshot, snapshot}} ->
        Agent.ack(ref, seq)
        if snapshot.status == :done, do: :ok, else: await_done(ref)
    after
      3000 -> flunk("context model timeout")
    end
  end

  test "step, delegation, peer and context limits reject explicitly" do
    ref = agent("limits")
    assert {:error, :invalid_or_busy_delegation} = Agent.delegate(ref, List.duplicate(%{}, 9))
    other = agent("peer-limit")
    for _ <- 1..16, do: assert({:ok, _} = Agent.peer_request(ref, other, %{"q" => "bounded"}))
    assert {:error, :peer_limit_or_invalid_message} = Agent.peer_request(ref, other, %{})

    assert {:error, :peer_limit_or_invalid_message} =
             Agent.peer_request(other, ref, String.duplicate("x", 8193))

    {:ok, catalogue} = Catalogue.new([Deterministic.descriptor()])

    {:ok, loop} =
      Agent.start(node(),
        id: "loop",
        model: TestBinding.binding("loop"),
        catalogue: catalogue,
        tools: %{"echo" => %{id: "echo", capability: "echo"}}
      )

    Agent.subscribe(loop)
    Agent.input(loop, "repeat")

    assert %{status: :error, final: :step_limit, steps: 16} = await_error(loop)

    messages = List.duplicate(%{"role" => "user", "content" => "bounded"}, 128)

    assert {:error, :context_limit} =
             Context.append(messages, [
               %{"role" => "user", "content" => "overflow"}
             ])

    assert {:error, :invalid_or_oversize_input} =
             Agent.input(other, String.duplicate("x", 65_537))
  end

  test "peer expiry, peer loss and subscriber DOWN preserve independent Agent lifetime" do
    source = agent("peer-source")
    target = agent("peer-target")
    {:ok, expired} = Agent.peer_request(source, target, %{}, 1)
    wait_inbox(source, expired)
    assert {:ok, %{result: {:error, :peer_expired}}} = Agent.peer_take(source, expired)
    {:ok, lost} = Agent.peer_request(source, target, %{})
    Agent.close(target)
    wait_inbox(source, lost)
    assert {:ok, %{result: {:error, :peer_lost}}} = Agent.peer_take(source, lost)

    sink =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    Agent.subscribe(source, sink)
    monitor = Process.monitor(sink)
    send(sink, :stop)
    assert_receive {:DOWN, ^monitor, _, _, _}
    assert {:ok, %{status: :idle}} = Agent.snapshot(source)
  end

  test "provider and gateway faults terminate active workers without replay" do
    for name <- [Beamlet.Node.Provider, Beamlet.Runtime.ExecutorGateway] do
      ref = agent("fault#{name}", "held")
      Agent.input(ref, "hold")
      assert_receive {:model, _, worker, _}, 3000
      monitor = Process.monitor(worker)
      Process.exit(Process.whereis(name), :kill)
      assert_receive {:DOWN, ^monitor, _, _, _}, 3000
      fresh_authority(100)
      TestBoot.barrier("model.provider:held")
      refute_receive {:model, _, _, _}, 20
    end
  end

  test "configured delegation continuation and stale group replies cannot revive a stopped turn" do
    parent = agent("continuation")
    Agent.subscribe(parent)

    spec = %{
      authority: node(),
      options: [id: "continuation-child", model: TestBinding.binding("plain")],
      input: "answer"
    }

    assert {:ok, _} = Agent.delegate(parent, [spec], continue: true)
    assert_receive {:beamlet_agent, ^parent, _, {:snapshot, %{status: :done, final: final}}}, 3000
    assert is_binary(final)
    assert {:ok, %{steps: 1}} = Agent.snapshot(parent)
    stopped = agent("stale-parent")

    held = %{
      authority: node(),
      options: [id: "stale-child", model: TestBinding.binding("held")],
      input: "hold"
    }

    {:ok, old_group} = Agent.delegate(stopped, [held])
    assert_receive {:model, _, _, _}, 3000
    Agent.stop_turn(stopped)
    send(stopped.pid, {:delegation_result, old_group, 0, nil, nil, {:ok, "stale"}})
    assert {:ok, %{status: :stopped, turn: nil}} = Agent.snapshot(stopped)
  end

  test "peer replies are isolated from a receiver's later turn" do
    source = agent("stale-source")
    target = agent("stale-target", "held")
    {:ok, id} = Agent.peer_request(source, target, %{})
    wait_inbox(target, id)
    Agent.input(target, "later turn")
    assert_receive {:model, _, _, _}, 3000
    assert {:error, :stale_peer_request} = Agent.peer_reply(target, id, %{})
    Agent.stop_turn(target)
    assert {:ok, %{status: :idle}} = Agent.snapshot(source)
  end

  test "coordinator loss without terminal notification fails the turn and cleans its worker" do
    ref = agent("lost-coordinator", "held")
    Agent.subscribe(ref)
    Agent.input(ref, "hold")
    assert_receive {:model, _, worker, _}, 3000
    monitor = Process.monitor(worker)
    [pending] = TestBoot.pending(ref)
    Process.exit(pending.ref.pid, :kill)

    assert_receive {:beamlet_agent, ^ref, _,
                    {:snapshot, %{status: :error, final: :infrastructure_lost}}},
                   3000

    assert_receive {:DOWN, ^monitor, _, _, _}, 3000
  end

  test "delegation expiry and terminal errors retain exact child turn correlation" do
    parent = agent("expiry-parent")
    Agent.subscribe(parent)

    spec = %{
      authority: node(),
      options: [id: "expiry-child", model: TestBinding.binding("held")],
      input: "hold"
    }

    {:ok, _} = Agent.delegate(parent, [spec])
    assert_receive {:model, _, worker, _}, 3000
    monitor = Process.monitor(worker)
    [{child_pid, _}] = Registry.lookup(Beamlet.Agent.Registry, "expiry-child")
    child = :sys.get_state(child_pid).ref
    [helper] = Map.values(:sys.get_state(parent.pid).children)
    # Inject a stale terminal snapshot followed by the timer signal from one sender.
    # The accepted outcome must be expiry, never this unrelated child turn.
    send(
      helper.pid,
      {:beamlet_agent, child, 99_999,
       {:snapshot, %{turn: nil, terminal_turn: make_ref(), status: :error, final: :stale}}}
    )

    send(helper.pid, :expired)

    assert_receive {:beamlet_agent, ^parent, _,
                    {:snapshot,
                     %{status: :done, final: [%{status: :error, value: :delegation_expired}]}}},
                   3000

    assert_receive {:DOWN, ^monitor, _, _, _}, 3000
    failed_parent = agent("failed-parent")
    Agent.subscribe(failed_parent)

    failed = %{
      authority: node(),
      options: [id: "failed-child", model: TestBinding.binding("absent")],
      input: "fail"
    }

    Agent.delegate(failed_parent, [failed])

    assert_receive {:beamlet_agent, ^failed_parent, _,
                    {:snapshot,
                     %{
                       status: :done,
                       final: [
                         %{status: :error, value: %{type: :model_failed, reason: :no_target}}
                       ]
                     }}},
                   3000
  end

  test "invalid sibling batch dispatches zero tools" do
    {:ok, catalogue} = Catalogue.new([TestTool.descriptor()])

    {:ok, ref} =
      Agent.start(node(),
        id: "batch",
        model: TestBinding.binding("bad"),
        catalogue: catalogue,
        tools: %{"workspace_read" => %{id: "tool", capability: "tool"}}
      )

    Agent.subscribe(ref)
    Agent.input(ref, "invalid siblings")
    assert_receive {:beamlet_agent, ^ref, _, {:snapshot, %{status: :error}}}, 3000
    refute_receive {:tool, _, _, _}, 50
  end

  test "several Agents concurrently run; stop freezes advancement and late results" do
    refs = for i <- 1..3, do: agent("held#{i}", "held")

    Enum.each(refs, fn ref ->
      Agent.subscribe(ref)
      Agent.input(ref, "hold")
    end)

    workers =
      for _ <- refs do
        assert_receive {:model, _, pid, _}, 3000
        pid
      end

    Enum.each(refs, &Agent.stop_turn/1)
    Enum.each(workers, &send(&1, :release))
    Enum.each(refs, fn ref -> assert {:ok, %{status: :stopped}} = Agent.snapshot(ref) end)
  end

  test "delegation joins child results without occupying parent executor slots" do
    parent = agent("parent")
    Agent.subscribe(parent)

    specs =
      for i <- 1..2,
          do: %{
            authority: node(),
            options: [id: "child#{i}", model: TestBinding.binding("held")],
            input: "hold"
          }

    assert {:ok, group} = Agent.delegate(parent, specs)
    assert_receive {:model, _, first, _}, 3000
    assert_receive {:model, _, second, _}, 3000
    assert {:ok, %{status: :waiting, turn: ^group}} = Agent.snapshot(parent)
    assert map_size(:sys.get_state(parent.pid).pending) == 0
    send(second, :release)
    send(first, :release)

    assert_receive {:beamlet_agent, ^parent, _,
                    {:snapshot, %{status: :done, final: [%{status: :ok}, %{status: :ok}]}}},
                   3000
  end

  test "delegation stop and delegator loss request owned child cleanup" do
    for action <- [:stop, :close] do
      parent = agent("parent#{action}")

      spec = %{
        authority: node(),
        options: [id: "child#{action}", model: TestBinding.binding("held")],
        input: "hold"
      }

      Agent.delegate(parent, [spec])
      assert_receive {:model, _, worker, _}, 3000
      monitor = Process.monitor(worker)
      if action == :stop, do: Agent.stop_turn(parent), else: Agent.close(parent)
      assert_receive {:DOWN, ^monitor, _, _, _}, 3000
    end
  end

  test "peer requests do not execute turns and lifetimes remain independent" do
    sender = agent("sender")
    receiver = agent("receiver")
    {:ok, id} = Agent.peer_request(sender, receiver, %{"question" => "hello"})
    # Messages from the sending Agent precede its call reply, but use receiver API as barrier.
    wait_inbox(receiver, id)
    assert {:ok, %{status: :idle}} = Agent.snapshot(receiver)
    assert :ok = Agent.peer_reply(receiver, id, %{"answer" => "world"})
    wait_inbox(sender, id)
    assert {:ok, %{result: {:ok, %{"answer" => "world"}}}} = Agent.peer_take(sender, id)
    Agent.close(sender)
    assert {:ok, %{status: :idle}} = Agent.snapshot(receiver)
  end

  test "slow subscriptions coalesce with bounded outstanding credits" do
    ref = agent("slow")
    Agent.subscribe(ref)
    for _ <- 1..40, do: Agent.stop_turn(ref)
    messages = drain(ref, [])
    assert length(messages) == 16
    {seq, _} = hd(messages)
    Agent.ack(ref, seq)
    assert_receive {:beamlet_agent, ^ref, _, {:snapshot, %{status: :stopped}}}
    sub = :sys.get_state(ref.pid).subscribers[self()]
    assert MapSet.size(sub.outstanding) == 16
  end

  test "registry and provider loss invalidate old refs and restart fresh infrastructure" do
    ref = agent("old")
    monitor = Process.monitor(ref.pid)
    Process.exit(Process.whereis(Beamlet.Agent.Registry), :kill)
    assert_receive {:DOWN, ^monitor, _, _, _}, 3000
    assert {:error, :unavailable} = Agent.snapshot(ref)
    provider = Process.whereis(Beamlet.Node.Provider)
    gateway = Process.whereis(Beamlet.Runtime.ExecutorGateway)
    monitor = Process.monitor(gateway)
    Process.exit(provider, :kill)
    assert_receive {:DOWN, ^monitor, _, _, _}, 3000
    fresh_authority(100)
    TestBoot.barrier("model.provider:held")
  end

  defp fresh_authority(0), do: flunk("fresh authority unavailable")

  defp fresh_authority(n) do
    case Agent.start(node(), id: "fresh", model: TestBinding.binding("plain")) do
      {:ok, ref} ->
        Agent.close(ref)

      _ ->
        receive do
        after
          10 -> fresh_authority(n - 1)
        end
    end
  end

  defp wait_inbox(ref, id, n \\ 100)
  defp wait_inbox(_, _, 0), do: flunk("peer inbox timeout")

  defp wait_inbox(ref, id, n) do
    {:ok, inbox} = Agent.inbox(ref)

    if Map.has_key?(inbox, id),
      do: :ok,
      else:
        (receive do
         after
           10 -> wait_inbox(ref, id, n - 1)
         end)
  end

  defp drain(ref, acc) do
    receive do
      {:beamlet_agent, ^ref, seq, event} -> drain(ref, [{seq, event} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
