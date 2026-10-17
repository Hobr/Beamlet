defmodule Beamlet.NodeDelegationBindingTest do
  use ExUnit.Case
  alias Beamlet.Agent
  alias Beamlet.Harness.Models.Deterministic
  @moduletag :distributed

  setup do
    assert Node.alive?()
    paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

    {:ok, peer, target} =
      :peer.start_link(%{
        name: String.to_atom("delegation_target_#{System.unique_integer([:positive])}"),
        connection: :standard_io,
        args: [~c"+S", ~c"2:2", ~c"-setcookie", Atom.to_charlist(Node.get_cookie())] ++ paths,
        wait_boot: 10_000,
        shutdown: 3000
      })

    Process.unlink(peer)
    on_exit(fn -> if Process.alive?(peer), do: :peer.stop(peer) end)
    assert :peer.call(peer, Node, :connect, [node()])

    assert :ok =
             :peer.call(peer, Beamlet.Node.TestBoot, :boot, [
               [
                 roles: [:authority, :executor],
                 model_providers: %{"child-only" => Deterministic},
                 limits: [refresh_ms: 20]
               ]
             ])

    assert :ok = :peer.call(peer, Beamlet.Node.TestBoot, :barrier, ["model.provider:child-only"])
    start_supervised!(Beamlet.Agent.AuthoritySupervisor)
    {:ok, parent} = Agent.start(node(), id: "parent", model: model_binding("deterministic"))
    :ok = Agent.subscribe(parent)
    %{peer: peer, target: target, parent: parent}
  end

  test "target-only binding completes direct and delegated child input", ctx do
    model = model_binding("child-only")
    assert {:ok, direct} = Agent.start(ctx.target, id: "direct", model: model)
    :ok = Agent.subscribe(direct)
    assert {:ok, _} = Agent.input(direct, "direct input")
    assert %{final: "child complete"} = terminal(direct)
    :ok = Agent.close(direct)

    assert {:ok, turn} = Agent.delegate(ctx.parent, [spec(ctx.target, "delegated", model)])
    assert %{turn: ^turn, final: [%{status: :ok, value: "child complete"}]} = terminal(ctx.parent)
    retired(ctx.parent)
    assert [] = :peer.call(ctx.peer, Registry, :lookup, [Beamlet.Agent.Registry, "delegated"])
    assert :sys.get_state(ctx.parent.pid).model == model_binding("deterministic")
  end

  test "target rejects parent-only, unknown and adapter-invalid bindings with correlated failure",
       ctx do
    :erlang.trace_pattern({Agent, :start, 2}, true, [:local])
    :erlang.trace_pattern({Deterministic, :validate_invocation, 1}, true, [:local])
    :erlang.trace(ctx.parent.pid, true, [:call])
    :erlang.trace(:new, true, [:call])

    on_exit(fn ->
      :erlang.trace(:all, false, [:call])
      :erlang.trace_pattern({Agent, :start, 2}, false, [:local])
      :erlang.trace_pattern({Deterministic, :validate_invocation, 1}, false, [:local])
    end)

    for {id, model} <- [
          {"parent-only", model_binding("deterministic")},
          {"unknown", model_binding("unknown")},
          {"bad-adapter", %{model_binding("child-only") | config: %{"unsupported" => true}}}
        ] do
      assert {:error, :invalid_agent_options} = Agent.start(ctx.target, id: id, model: model)
      assert {:ok, turn} = Agent.delegate(ctx.parent, [spec(ctx.target, id, model)])

      assert %{turn: ^turn, final: [%{status: :error, value: :authority_unavailable}]} =
               terminal(ctx.parent)

      retired(ctx.parent)
      assert [] = :peer.call(ctx.peer, Registry, :lookup, [Beamlet.Agent.Registry, id])

      assert_receive {:trace, _, :call, {Agent, :start, [target, options]}}
      assert target == ctx.target
      assert options[:id] == id
    end

    # Exactly one delegated creation attempt per binding; no retries or late dispatch.
    refute_receive {:trace, _, :call, {Agent, :start, _}}, 50
    refute_receive {:trace, _, :call, {Deterministic, :validate_invocation, _}}, 50
    refute_receive {:beamlet_agent, _, _, {:snapshot, %{status: :waiting}}}, 50
  end

  test "portable malformed and oversized options reject before spawning or dispatch", ctx do
    good = model_binding("child-only")

    bad = [
      Map.put(good, :provider, "bad provider"),
      Map.put(good, :module, Deterministic),
      Map.put(good, :config, %{"api_key" => "wrong field"}),
      Map.put(good, :config, %{"large" => String.duplicate("x", 16_384)}),
      Map.put(good, :credentials, %{"ROOT" => "x"}),
      Map.put(good, :credentials, %{"token" => String.duplicate("x", 16_384)}),
      Map.put(good, :credentials, %{"token" => self()}),
      Map.put(good, :placement, %{budget_ms: 1}),
      Map.put(good, :placement, %{claims: %{"x" => -1}}),
      Map.put(good, :placement, %{allowed_nodes: ["not an atom"]})
    ]

    :erlang.trace(ctx.parent.pid, true, [:procs])

    on_exit(fn ->
      if Process.alive?(ctx.parent.pid), do: :erlang.trace(ctx.parent.pid, false, [:procs])
    end)

    options =
      Enum.map(bad, &[id: "bad-local", model: &1]) ++
        [
          [id: "bad-local", model: good, catalogue: %{"bad" => %{}}],
          [id: "bad-local", model: good, tools: %{"bad" => %{}}],
          [id: "bad-local", model: good, models: [good]],
          [id: "bad-local", model: good, delegator: "bad"]
        ]

    for opts <- options do
      assert {:error, :invalid_or_busy_delegation} =
               Agent.delegate(ctx.parent, [%{authority: ctx.target, options: opts, input: "x"}])
    end

    refute_receive {:trace, _, :spawn, _, _}, 50
    assert %{status: :idle, children: children, helpers: helpers} = :sys.get_state(ctx.parent.pid)
    assert children == %{} and helpers == %{}
    assert [] = :peer.call(ctx.peer, Registry, :lookup, [Beamlet.Agent.Registry, "bad-local"])
  end

  defp model_binding(provider),
    do: %{
      provider: provider,
      config: %{"reply" => %{"kind" => "text", "content" => "child complete", "calls" => []}}
    }

  defp spec(target, id, model),
    do: %{authority: target, options: [id: id, model: model], input: "child input"}

  defp terminal(ref) do
    receive do
      {:beamlet_agent, ^ref, seq, {:snapshot, snapshot}} ->
        :ok = Agent.ack(ref, seq)
        if snapshot.status in [:done, :error, :stopped], do: snapshot, else: terminal(ref)
    after
      5000 -> flunk("terminal timeout")
    end
  end

  defp retired(ref, n \\ 200) do
    if map_size(:sys.get_state(ref.pid).helpers) > 0 do
      assert n > 0
      Process.sleep(10)
      retired(ref, n - 1)
    end
  end
end
