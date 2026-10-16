defmodule Beamlet.NodeReviewTest do
  use ExUnit.Case
  alias Beamlet.Actions.{Operation, Result}
  alias Beamlet.Agent
  alias Beamlet.Agent.Integration.{Caller, Handler}
  alias Beamlet.Agent.OperationOwner
  alias Beamlet.Agent.Server
  alias Beamlet.Harness.Catalogue
  alias Beamlet.Harness.Models.OpenAICompatible
  alias Beamlet.Node.{TestBoot, TestModel}

  defmodule InconsistentModel do
    def complete(_, _, _) do
      {:ok,
       %{
         kind: :text,
         content: "different",
         calls: [],
         assistant: %{"role" => "assistant", "content" => "original"}
       }}
    end
  end

  defmodule ProgressModel do
    def complete(_, settings, context) do
      send(settings.observer, {:progress_worker, self()})
      receive do: (:release -> :ok)
      context.progress.("native progress")

      OpenAICompatible.normalize(
        %{
          "choices" => [
            %{
              "finish_reason" => "stop",
              "message" => %{"role" => "assistant", "content" => "done"}
            }
          ]
        },
        %{}
      )
    end
  end

  defmodule UnencodableTool do
    alias Beamlet.Harness.Tools.Deterministic
    def descriptor, do: Deterministic.descriptor()
    def invoke(_, _, _), do: {:ok, %{%{} => "native data"}}
  end

  setup do
    profiles = %{
      "progress" => %{
        type: :model,
        module: ProgressModel,
        settings: %{observer: self()},
        capability: "progress"
      },
      "loop" => %{
        type: :model,
        module: Beamlet.Node.TestLoopModel,
        settings: %{},
        capability: "loop"
      },
      "echo" => %{type: :tool, module: UnencodableTool, settings: %{}, capability: "echo"},
      "held" => %{
        type: :model,
        module: TestModel,
        settings: %{hold: true, observer: self()},
        capability: "held"
      },
      "inconsistent" => %{
        type: :model,
        module: InconsistentModel,
        settings: %{},
        capability: "inconsistent"
      }
    }

    start_supervised!(
      {Beamlet.Node,
       roles: [:authority, :executor],
       profiles: profiles,
       allowlist: %{
         model: [TestModel, InconsistentModel, Beamlet.Node.TestLoopModel, ProgressModel],
         tool: [UnencodableTool]
       },
       limits: [refresh_ms: 20]}
    )

    TestBoot.barrier("held")
    :ok
  end

  test "OperationOwner preserves public Runtime invalid, current-cap and unavailable errors" do
    {:ok, operation} = Operation.new(kind: "agent.native")
    assert_owner_error(%{operation | budget_ms: 0}, :invalid_operation)

    # Change the live deployment ceiling after authority startup.
    :sys.replace_state(Beamlet.Runtime.Directory, fn s ->
      %{s | limits: %{s.limits | operation_bytes: 1024}}
    end)

    assert_owner_error(
      %{operation | payload: %{"data" => String.duplicate("x", 1200)}},
      :invalid_operation
    )

    for name <- [Beamlet.Runtime.Directory, Beamlet.Runtime.Coordinators] do
      pid = Process.whereis(name)
      Process.unregister(name)

      try do
        assert_owner_error(operation, :unavailable)
      after
        Process.register(pid, name)
      end
    end

    :sys.replace_state(Beamlet.Runtime.Coordinators, fn s -> %{s | max_children: 0} end)
    assert_owner_error(operation, :capacity)
  end

  defp assert_owner_error(operation, reason) do
    assert Beamlet.Runtime.submit(operation) == {:error, reason}
    parent = self()
    token = make_ref()

    owner =
      spawn(fn ->
        OperationOwner.run(
          parent,
          token,
          operation,
          Process.whereis(Beamlet.Agent.Resources)
        )
      end)

    mon = Process.monitor(owner)
    assert_receive {:operation_failed, ^token, {:error, ^reason}}, 1000
    assert_receive {:DOWN, ^mon, :process, ^owner, _}, 1000
    refute_receive {:operation_ready, ^token, _}
  end

  defp agent(id, profile \\ "held") do
    {:ok, ref} = Agent.start(node(), id: id, model: %{id: profile, capability: profile})
    ref
  end

  defp resources do
    Beamlet.Agent.Resources
    |> :sys.get_state()
    |> Map.fetch!(:processes)
    |> Map.values()
    |> Enum.uniq()
  end

  defp down_all(pids, action) do
    monitors = Enum.map(pids, &Process.monitor/1)
    action.()
    for monitor <- monitors, do: assert_receive({:DOWN, ^monitor, :process, _, _}, 3000)
  end

  test "duplicate lifecycle registration and tracking retain one inventory entry per PID" do
    manager = Process.whereis(Beamlet.Agent.Resources)
    controller = spawn(fn -> receive do: (:stop -> :ok) end)

    worker =
      spawn(fn ->
        Process.link(controller)
        receive do: (:stop -> :ok)
      end)

    on_exit(fn ->
      Process.exit(controller, :kill)
      Process.exit(worker, :kill)
    end)

    for _ <- 1..3 do
      send(manager, {:register, controller, make_ref(), self(), :operation})
    end

    for _ <- 1..100, do: send(manager, {:track, controller, worker})
    state = :sys.get_state(manager)
    assert map_size(state.slots) == 1
    assert Enum.sort(Map.values(state.processes)) == Enum.sort([controller, worker])
    assert length(:persistent_term.get({Beamlet.Agent.Resources, :generation})) == 2

    down_all([controller, worker], fn -> Process.exit(controller, :kill) end)
    assert_receive {:resource_retired, ^controller}, 3000
    assert :sys.get_state(manager).slots == %{}
  end

  test "operation admission dies before suspended coordinators resume and cannot replay" do
    ref = agent("bounded-admission")
    supervisor = Process.whereis(Beamlet.Runtime.Coordinators)
    :sys.suspend(supervisor)
    on_exit(fn -> if Process.alive?(supervisor), do: :sys.resume(supervisor) end)
    Agent.input(ref, "must never execute")
    Agent.snapshot(ref)
    [owner] = Map.values(:sys.get_state(ref.pid).owners)
    down_all([owner.pid | resources()], fn -> Agent.close(ref) end)
    assert :ok = Supervisor.terminate_child(Beamlet.Node, Beamlet.Agent.AuthoritySupervisor)
    :sys.resume(supervisor)
    assert DynamicSupervisor.count_children(supervisor).active == 0
    refute_receive {:model, _, _, _}, 100
  end

  test "authority resource restart fences old admission resources before new readiness" do
    ref = agent("restart-admission")
    coordinators = Process.whereis(Beamlet.Runtime.Coordinators)
    :sys.suspend(coordinators)
    on_exit(fn -> if Process.alive?(coordinators), do: :sys.resume(coordinators) end)
    Agent.input(ref, "never replay")
    Agent.snapshot(ref)
    manager = Process.whereis(Beamlet.Agent.Resources)
    [owner] = Map.values(:sys.get_state(ref.pid).owners)

    down_all([ref.pid, owner.pid | resources()], fn ->
      Process.exit(manager, :kill)
    end)

    Supervisor.which_children(Beamlet.Agent.AuthoritySupervisor)
    assert Process.whereis(Beamlet.Agent.Resources) != manager
    replacement = agent("after-restart")
    Agent.close(replacement)
    :sys.resume(coordinators)
    assert DynamicSupervisor.count_children(coordinators).active == 0
    refute_receive {:model, _, _, _}, 100
  end

  test "stale registration and tracking after resource suspension cannot admit business work" do
    ref = agent("stale-resource-admission")
    manager = Process.whereis(Beamlet.Agent.Resources)
    :sys.suspend(manager)
    on_exit(fn -> if Process.alive?(manager), do: :sys.resume(manager) end)
    Agent.input(ref, "never")
    Agent.snapshot(ref)
    [owner] = Map.values(:sys.get_state(ref.pid).owners)
    down_all([owner.pid], fn -> Agent.close(ref) end)
    late = spawn(fn -> receive do: (:never -> :ok) end)
    monitor = Process.monitor(late)
    send(manager, {:track, owner.pid, late})
    :sys.resume(manager)
    assert_receive {:DOWN, ^monitor, :process, ^late, :killed}, 3000
    state = :sys.get_state(manager)
    assert state.slots == %{}
    assert state.rejected == %{}
    refute_receive {:model, _, _, _}, 100
  end

  test "parent loss bounds local Agent admission before resume" do
    parent = agent("bounded-parent")
    supervisor = Process.whereis(Beamlet.Agent.Agents)
    :sys.suspend(supervisor)
    on_exit(fn -> if Process.alive?(supervisor), do: :sys.resume(supervisor) end)

    spec = %{
      authority: node(),
      options: [id: "late-child", model: %{id: "held", capability: "held"}],
      input: "never"
    }

    Agent.delegate(parent, [spec])
    Agent.snapshot(parent)
    [launcher] = Map.values(:sys.get_state(parent.pid).children)
    down_all([launcher.pid | resources()], fn -> Agent.close(parent) end)
    :sys.resume(supervisor)
    assert DynamicSupervisor.count_children(supervisor).active == 0
    assert Registry.lookup(Beamlet.Agent.Registry, "late-child") == []
    refute_receive {:model, _, _, _}, 100
  end

  test "authority teardown bounds local Agent admission while Agents remains suspended" do
    parent = agent("teardown-local-parent")
    agents = Process.whereis(Beamlet.Agent.Agents)
    :sys.suspend(agents)

    spec = %{
      authority: node(),
      options: [id: "teardown-local-child", model: %{id: "held", capability: "held"}],
      input: "never"
    }

    Agent.delegate(parent, [spec])
    Agent.snapshot(parent)
    [launcher] = Map.values(:sys.get_state(parent.pid).children)
    helper = delegation_helper(100)

    down_all([agents, parent.pid, launcher.pid, helper | resources()], fn ->
      assert :ok = Supervisor.terminate_child(Beamlet.Node, Beamlet.Agent.AuthoritySupervisor)
    end)

    refute_receive {:model, _, _, _}, 100
  end

  defp delegation_helper(left) do
    case Task.Supervisor.children(Beamlet.Agent.Delegations) do
      [helper] ->
        helper

      [] ->
        assert left > 0
        Process.sleep(10)
        delegation_helper(left - 1)
    end
  end

  test "authority teardown interrupts suspended Task admission without resuming it" do
    parent = agent("authority-parent")
    supervisor = Process.whereis(Beamlet.Agent.Delegations)
    :sys.suspend(supervisor)

    spec = %{
      authority: node(),
      options: [id: "authority-child", model: %{id: "held", capability: "held"}],
      input: "never"
    }

    Agent.delegate(parent, [spec])
    Agent.snapshot(parent)
    [launcher] = Map.values(:sys.get_state(parent.pid).children)

    down_all([supervisor, parent.pid, launcher.pid | resources()], fn ->
      assert :ok = Supervisor.terminate_child(Beamlet.Node, Beamlet.Agent.AuthoritySupervisor)
    end)

    refute_receive {:model, _, _, _}, 100
  end

  test "nested delegation cleanup kills suspended child processes and all helpers" do
    parent = agent("nested-parent")

    spec = %{
      authority: node(),
      options: [id: "nested-child", model: %{id: "held", capability: "held"}],
      input: "hold"
    }

    Agent.delegate(parent, [spec])
    assert_receive {:model, _, worker, _}, 3000
    [{child_pid, _}] = Registry.lookup(Beamlet.Agent.Registry, "nested-child")
    child = :sys.get_state(child_pid).ref
    {:links, links} = Process.info(child_pid, :links)
    helper = Enum.find(links, &(&1 != Process.whereis(Beamlet.Agent.Agents)))
    :erlang.suspend_process(helper)
    Agent.stop_turn(child)

    grand_spec =
      put_in(spec.options, id: "nested-grandchild", model: %{id: "held", capability: "held"})

    Agent.delegate(child, [grand_spec])
    assert_receive {:model, _, grand_worker, _}, 3000
    [{grand_pid, _}] = Registry.lookup(Beamlet.Agent.Registry, "nested-grandchild")
    :sys.suspend(child_pid)
    :sys.suspend(grand_pid)

    down_all([child_pid, grand_pid, worker, grand_worker | resources()], fn ->
      Agent.close(parent)
    end)
  end

  test "genuine progress and terminal with blocked ack retain every live owner until DOWN" do
    ref = agent("native-ack", "progress")
    Agent.input(ref, "hello")
    assert_receive {:progress_worker, worker}, 3000
    [pending] = TestBoot.pending(ref)
    [owner] = Map.values(:sys.get_state(ref.pid).owners)
    monitor = Process.monitor(owner.pid)
    :sys.suspend(ref.pid)
    send(worker, :release)
    wait_terminal(ref.pid, 100)
    :sys.suspend(pending.ref.pid)
    on_exit(fn -> if Process.alive?(pending.ref.pid), do: :sys.resume(pending.ref.pid) end)
    :sys.resume(ref.pid)
    assert {:ok, %{status: :done, final: "done"}} = Agent.snapshot(ref)
    state = :sys.get_state(ref.pid)

    assert not Process.alive?(owner.pid) or
             Enum.any?(state.owners, fn {_, o} -> o.pid == owner.pid end)

    assert_receive {:DOWN, ^monitor, :process, _, _}, 3000
    assert {:ok, _} = Agent.input(ref, "next")
    assert_receive {:progress_worker, next_worker}, 3000
    assert map_size(:sys.get_state(ref.pid).owners) <= 8
    send(next_worker, :release)
    Agent.close(ref)
  end

  defp wait_terminal(pid, left) do
    {:messages, messages} = Process.info(pid, :messages)

    unless Enum.any?(messages, &match?({:beamlet_operation, _, {:result, _}}, &1)) do
      assert left > 0
      Process.sleep(10)
      wait_terminal(pid, left - 1)
    end
  end

  test "inconsistent normalized native reply fails without poisoning retained context" do
    ref = agent("canonical", "inconsistent")
    Agent.subscribe(ref)
    Agent.input(ref, "hello")

    assert_receive {:beamlet_agent, ^ref, _,
                    {:snapshot, %{status: :error, final: :invalid_reply}}},
                   3000

    assert :sys.get_state(ref.pid).messages == [%{"role" => "user", "content" => "hello"}]
  end

  test "helper crash tears down its owned child and worker without parent death" do
    parent = agent("helper-parent")
    Agent.subscribe(parent)

    spec = %{
      authority: node(),
      options: [id: "helper-child", model: %{id: "held", capability: "held"}],
      input: "hold"
    }

    Agent.delegate(parent, [spec])
    assert_receive {:model, _, worker, _}, 3000
    [{child, _}] = Registry.lookup(Beamlet.Agent.Registry, "helper-child")
    child_monitor = Process.monitor(child)
    worker_monitor = Process.monitor(worker)
    [helper] = Map.values(:sys.get_state(parent.pid).children)
    Process.exit(helper.pid, :kill)
    assert_receive {:DOWN, ^child_monitor, _, _, _}, 3000
    assert_receive {:DOWN, ^worker_monitor, _, _, _}, 3000

    assert_receive {:beamlet_agent, ^parent, _,
                    {:snapshot, %{status: :done, final: [%{status: :error, value: :child_lost}]}}},
                   3000

    assert Process.alive?(parent.pid)
  end

  test "malformed delegation rejects without terminating the parent" do
    ref = agent("invalid-spec")

    for options <- [nil, %{}, 1] do
      assert {:error, :invalid_or_busy_delegation} =
               Agent.delegate(ref, [%{authority: node(), options: options, input: "x"}])
    end

    assert {:ok, %{status: :idle}} = Agent.snapshot(ref)
  end

  test "executor rejects extra executable fields before native provider invocation" do
    context = %{
      settings: %{"p" => %{type: :model, module: OpenAICompatible, settings: %{}}},
      progress: nil,
      cancelled?: nil
    }

    request = %{"messages" => [%{"role" => "user", "content" => "x"}], "catalogue" => %{}}
    payload = %{"profile" => "p", "request" => request}
    assert {:error, :invalid_request} = Handler.run(Map.put(payload, "extra", true), context)

    assert {:error, :invalid_request} =
             Handler.run(%{payload | "request" => Map.put(request, "extra", true)}, context)
  end

  test "allowlisting a module with missing native callbacks rejects registration" do
    assert {:error, :invalid_node_configuration} =
             Beamlet.Node.configuration(
               roles: [:executor],
               allowlist: %{model: [String], tool: []},
               profiles: %{
                 "invalid" => %{
                   type: :model,
                   module: String,
                   settings: %{},
                   capability: "invalid"
                 }
               }
             )
  end

  test "Runtime-valid non-JSON Tool output fails safely and preserves complete context" do
    {:ok, catalogue} = Catalogue.new([UnencodableTool.descriptor()])

    {:ok, ref} =
      Agent.start(node(),
        id: "non-json",
        model: %{id: "loop", capability: "loop"},
        catalogue: catalogue,
        tools: %{"echo" => %{id: "echo", capability: "echo"}}
      )

    Agent.subscribe(ref)
    Agent.input(ref, "loop")

    assert_receive {:beamlet_agent, ^ref, _,
                    {:snapshot, %{status: :error, final: :invalid_tool_observation}}},
                   3000

    assert Process.alive?(ref.pid)
    state = :sys.get_state(ref.pid)
    assert state.messages == [%{"role" => "user", "content" => "loop"}]
    assert state.results == %{}
    assert state.order == []
  end

  test "malformed terminal with matching live ref is ignored before context mutation" do
    ref = agent("malformed-terminal")
    Agent.input(ref, "hold")
    assert_receive {:model, _, worker, _}, 3000
    [pending] = TestBoot.pending(ref)

    send(
      ref.pid,
      {:beamlet_operation, pending.ref,
       {:result,
        %Result{
          operation_id: pending.ref.id,
          status: :ok,
          value: %{},
          source: :execution
        }}}
    )

    assert {:ok, %{status: :running}} = Agent.snapshot(ref)
    send(worker, :release)
    Agent.subscribe(ref)
    assert_receive {:beamlet_agent, ^ref, _, {:snapshot, %{status: :done}}}, 3000
  end

  test "Directory suspension does not block commands or late submission cleanup" do
    ref = agent("blocked-directory")
    directory = Process.whereis(Beamlet.Runtime.Directory)
    :sys.suspend(directory)
    on_exit(fn -> if Process.alive?(directory), do: :sys.resume(directory) end)
    assert {:ok, _} = Agent.input(ref, "hold")
    assert {:ok, %{status: :running}} = Agent.snapshot(ref)
    assert :ok = Agent.stop_turn(ref)
    assert {:ok, %{status: :stopped}} = Agent.snapshot(ref)
    owners = :sys.get_state(ref.pid).owners
    monitors = Enum.map(owners, fn {_, o} -> Process.monitor(o.pid) end)
    :sys.resume(directory)
    for monitor <- monitors, do: assert_receive({:DOWN, ^monitor, _, _, _}, 3000)
    assert {:ok, %{status: :stopped}} = Agent.snapshot(ref)
  end

  test "unavailable configured Directory never widens the captured executable cap" do
    directory = Process.whereis(Beamlet.Runtime.Directory)
    :sys.suspend(directory)
    on_exit(fn -> if Process.alive?(directory), do: :sys.resume(directory) end)
    profile = %{id: "held", capability: "held"}

    startup =
      Task.async(fn ->
        Server.start_link(id: "unavailable-cap", model: profile)
      end)

    construction = Task.async(fn -> Caller.operation(profile, %{}) end)
    assert {:error, :runtime_unavailable} = Task.await(startup, 6000)
    assert {:error, :runtime_unavailable} = Task.await(construction, 6000)
    assert Registry.lookup(Beamlet.Agent.Registry, "unavailable-cap") == []
    :sys.resume(directory)
    assert {:ok, _} = Agent.start(node(), id: "unavailable-cap", model: profile)
  end

  test "operation owner loss before readiness fails the turn explicitly" do
    ref = agent("lost-owner-before-ready")
    Agent.subscribe(ref)
    supervisor = Process.whereis(Beamlet.Runtime.Coordinators)
    :sys.suspend(supervisor)
    on_exit(fn -> if Process.alive?(supervisor), do: :sys.resume(supervisor) end)
    assert {:ok, _} = Agent.input(ref, "hold")
    assert {:ok, %{status: :running}} = Agent.snapshot(ref)
    [owner] = Map.values(:sys.get_state(ref.pid).owners)
    monitor = Process.monitor(owner.pid)
    Process.exit(owner.pid, :kill)
    assert_receive {:DOWN, ^monitor, _, _, _}, 3000

    assert_receive {:beamlet_agent, ^ref, _,
                    {:snapshot, %{status: :error, final: :infrastructure_lost}}},
                   1000

    :sys.resume(supervisor)
    assert {:ok, %{status: :error}} = Agent.snapshot(ref)
  end

  test "suspended coordinator cannot stall stop or snapshots" do
    ref = agent("blocked-coordinator")
    Agent.input(ref, "hold")
    assert_receive {:model, _, _, _}, 3000
    [pending] = TestBoot.pending(ref)
    :sys.suspend(pending.ref.pid)
    on_exit(fn -> if Process.alive?(pending.ref.pid), do: :sys.resume(pending.ref.pid) end)
    assert :ok = Agent.stop_turn(ref)
    assert {:ok, %{status: :stopped}} = Agent.snapshot(ref)
    :sys.resume(pending.ref.pid)
  end

  test "progress binds attempt and sequence and rejects terminal mismatch" do
    ref = agent("progress-binding")
    Agent.input(ref, "hold")
    assert_receive {:model, _, _, _}, 3000
    [pending] = TestBoot.pending(ref)
    send(ref.pid, {:beamlet_operation, pending.ref, {:progress, "attempt-a", 2, "accepted"}})

    for {attempt, sequence} <- [{"attempt-a", 2}, {"attempt-a", 1}, {"attempt-b", 3}] do
      send(ref.pid, {:beamlet_operation, pending.ref, {:progress, attempt, sequence, "rejected"}})
    end

    assert {:ok, %{progress: %{value: "accepted"}}} = Agent.snapshot(ref)

    send(
      ref.pid,
      {:beamlet_operation, %{pending.ref | pid: self()}, {:progress, "attempt-a", 9, "wrong-ref"}}
    )

    send(ref.pid, {:beamlet_operation, pending.ref, {:progress, "attempt-a", 3, "newer"}})
    assert {:ok, %{progress: %{value: "newer"}}} = Agent.snapshot(ref)

    result = %Result{
      operation_id: pending.ref.id,
      status: :ok,
      value: %{},
      source: :execution,
      execution_id: "execution-b",
      metadata: %{attempt_id: "attempt-b"}
    }

    assert Result.valid?(result)
    send(ref.pid, {:beamlet_operation, pending.ref, {:result, result}})
    assert {:ok, %{status: :running}} = Agent.snapshot(ref)
    assert map_size(:sys.get_state(ref.pid).pending) == 1
    Agent.stop_turn(ref)
    send(ref.pid, {:beamlet_operation, pending.ref, {:progress, "attempt-a", 99, "stale-turn"}})
    assert {:ok, %{status: :stopped, progress: %{value: "newer"}}} = Agent.snapshot(ref)
  end

  test "delayed child creation checks stop and parent loss before input" do
    for action <- [:stop, :loss] do
      parent = agent("delayed-parent-#{action}")
      supervisor = Process.whereis(Beamlet.Agent.Agents)
      :sys.suspend(supervisor)

      spec = %{
        authority: node(),
        options: [id: "delayed-child-#{action}", model: %{id: "held", capability: "held"}],
        input: "must not run"
      }

      assert {:ok, _} = Agent.delegate(parent, [spec])
      [launcher] = Map.values(:sys.get_state(parent.pid).children)
      monitor = Process.monitor(launcher.pid)
      if action == :stop, do: Agent.stop_turn(parent), else: Process.exit(parent.pid, :kill)
      :sys.resume(supervisor)
      assert_receive {:DOWN, ^monitor, _, _, _}, 3000
      assert Registry.lookup(Beamlet.Agent.Registry, "delayed-child-#{action}") == []
      refute_receive {:model, _, _, _}, 50
    end
  end

  test "blocked helper admission keeps cleanup slots until DOWN" do
    parent = agent("admission-parent")
    supervisor = Process.whereis(Beamlet.Agent.Delegations)
    :sys.suspend(supervisor)

    spec = %{
      authority: node(),
      options: [id: "admission-child", model: %{id: "held", capability: "held"}],
      input: "must not run"
    }

    assert {:ok, _} = Agent.delegate(parent, [spec])
    [launcher] = Map.values(:sys.get_state(parent.pid).helpers)
    monitor = Process.monitor(launcher)
    assert :ok = Agent.stop_turn(parent)
    assert_receive {:DOWN, ^monitor, _, _, _}, 3000
    :sys.resume(supervisor)
    refute_receive {:model, _, _, _}, 50
  end

  test "partial helper admission failure retains cleanup accounting" do
    parent = agent("partial-parent")
    Agent.subscribe(parent)
    tasks = Process.whereis(Beamlet.Agent.Delegations)
    original = :sys.get_state(tasks)
    :sys.replace_state(tasks, &%{&1 | max_children: 1})
    agents = Process.whereis(Beamlet.Agent.Agents)
    :sys.suspend(agents)

    on_exit(fn ->
      if Process.alive?(agents), do: :sys.resume(agents)
      if Process.alive?(tasks), do: :sys.replace_state(tasks, fn _ -> original end)
    end)

    specs =
      for id <- ["partial-a", "partial-b"],
          do: %{
            authority: node(),
            options: [id: id, model: %{id: "held", capability: "held"}],
            input: "must not run"
          }

    assert {:ok, _} = Agent.delegate(parent, specs)

    assert_receive {:beamlet_agent, ^parent, _,
                    {:snapshot, %{status: :error, final: :delegation_capacity}}},
                   3000

    monitors = for pid <- Map.values(:sys.get_state(parent.pid).helpers), do: Process.monitor(pid)
    for monitor <- monitors, do: assert_receive({:DOWN, ^monitor, _, _, _}, 3000)
    :sys.resume(agents)
    refute_receive {:model, _, _, _}, 50
  end

  test "Agent loss during delayed submission cleans late-created work" do
    ref = agent("lost-submitter")
    directory = Process.whereis(Beamlet.Runtime.Directory)
    :sys.suspend(directory)
    on_exit(fn -> if Process.alive?(directory), do: :sys.resume(directory) end)
    assert {:ok, _} = Agent.input(ref, "hold")
    assert {:ok, %{status: :running}} = Agent.snapshot(ref)
    monitors = for {_, owner} <- :sys.get_state(ref.pid).owners, do: Process.monitor(owner.pid)
    Process.exit(ref.pid, :kill)
    :sys.resume(directory)
    for monitor <- monitors, do: assert_receive({:DOWN, ^monitor, _, _, _}, 3000)
  end

  test "peer request envelope accepts exactly the cap and rejects the next byte" do
    source = agent(String.duplicate("a", 128))
    target = agent(String.duplicate("b", 128))
    empty = {:peer_request, target, source, nil, make_ref(), "", 60_000}
    payload = String.duplicate("x", 8192 - :erlang.external_size(empty))
    assert :erlang.external_size(put_elem(empty, 5, payload)) == 8192

    assert {:error, :peer_limit_or_invalid_message} =
             Agent.peer_request(source, target, payload <> "x", 60_000)

    assert {:ok, id} = Agent.peer_request(source, target, payload, 60_000)
    assert {:ok, inbox} = Agent.inbox(target)
    assert inbox[id].payload == payload
    assert :erlang.external_size({id, inbox[id]}) <= 8192
    empty_reply = {:peer_response, source, target, nil, id, {:ok, ""}}
    reply = String.duplicate("r", 8192 - :erlang.external_size(empty_reply))
    assert {:error, :message_limit} = Agent.peer_reply(target, id, reply <> "r")
    assert :ok = Agent.peer_reply(target, id, reply)
  end

  test "complete peer envelopes with maximum identities fit the cap" do
    source = agent(String.duplicate("s", 128))
    target = agent(String.duplicate("t", 128))

    assert {:error, :peer_limit_or_invalid_message} =
             Agent.peer_request(source, target, String.duplicate("x", 8100))

    assert {:ok, id} = Agent.peer_request(source, target, String.duplicate("x", 7000), 60_000)
    assert {:ok, inbox} = Agent.inbox(target)
    assert :erlang.external_size({id, inbox[id]}) <= 8192
    assert {:error, :message_limit} = Agent.peer_reply(target, id, String.duplicate("x", 8100))
    assert :ok = Agent.peer_reply(target, id, String.duplicate("x", 7000))
    assert {:ok, inbox} = Agent.inbox(source)
    assert :erlang.external_size({id, inbox[id]}) <= 8192
  end
end
