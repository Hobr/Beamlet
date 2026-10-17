defmodule Beamlet.NodeModelBindingTest do
  use ExUnit.Case
  alias Beamlet.Agent
  alias Beamlet.Agent.Integration.{Caller, Handler}
  alias Beamlet.Harness.Catalogue
  alias Beamlet.Harness.Tools.Deterministic
  alias Beamlet.Node.{AlternateModel, TestBoot}

  defmodule RaisingModel do
    def validate_invocation(_), do: raise("synthetic-private-error")
    def complete(_, _, _), do: raise("must not call")
  end

  setup do
    Process.register(self(), :alternate_test_observer)
    registry = %{"alternate" => AlternateModel, "raising" => RaisingModel}

    start_supervised!(
      {Beamlet.Node,
       roles: [:authority, :executor],
       model_providers: registry,
       allowlist: %{tool: [Beamlet.Node.ObservedTool]},
       profiles: %{
         "echo" => %{
           type: :tool,
           module: Beamlet.Node.ObservedTool,
           settings: %{observer: self()},
           capability: "echo"
         }
       },
       limits: [refresh_ms: 20]}
    )

    TestBoot.barrier("model.provider:alternate")
    :ok
  end

  defp binding(dialect, key),
    do: %{
      provider: "alternate",
      config: %{"dialect" => dialect},
      credentials: %{"session" => %{"bearer" => key}},
      placement: %{claims: %{}}
    }

  test "two immutable bindings share executor through neutral Tool flow and a later turn" do
    {:ok, catalogue} = Catalogue.new([Deterministic.descriptor()])

    refs =
      for {dialect, key} <- [
            {"alpha", "synthetic-alpha-secret"},
            {"beta", "synthetic-beta-secret"}
          ] do
        model = binding(dialect, key)

        {:ok, ref} =
          Agent.start(node(),
            id: dialect,
            model: model,
            catalogue: catalogue,
            tools: %{"echo" => %{id: "echo", capability: "echo"}}
          )

        :ok = Agent.subscribe(ref)
        {:ok, _} = Agent.input(ref, "begin")
        {ref, model}
      end

    for {ref, model} <- refs do
      await_done(ref)
      assert :sys.get_state(ref.pid).model == model
      messages = :sys.get_state(ref.pid).messages
      assert Enum.any?(messages, &(&1["call_id"] == "alternate-call"))
      {:ok, snapshot} = Agent.snapshot(ref)
      assert_clean(snapshot)
      assert_clean(messages)
      wait_retired(ref)
      {:ok, _} = Agent.input(ref, "later")
      await_done(ref)
      assert :sys.get_state(ref.pid).model == model
    end

    invocations =
      for _ <- 1..6 do
        assert_receive {:alternate_invocation, invocation}
        invocation
      end

    for {_, model} <- refs,
        do:
          assert(Enum.count(invocations, &(&1 == Map.take(model, [:config, :credentials]))) == 3)

    for _ <- 1..2 do
      assert_receive {:tool_context, context, settings, args}
      refute Map.has_key?(context, :credentials)
      refute Map.has_key?(context, :config)
      assert_clean(settings)
      assert_clean(args)
    end

    {parent, _} = hd(refs)

    assert {:error, :invalid_or_busy_delegation} =
             Agent.delegate(parent, [
               %{authority: node(), options: [id: "implicit-child"], input: "x"}
             ])

    {other, other_binding} = List.last(refs)
    {:ok, _} = Agent.peer_request(parent, other, %{"hello" => true})
    assert :sys.get_state(other.pid).model == other_binding
    assert_clean(elem(Agent.inbox(other), 1))
  end

  test "binding rejects unknown providers, fields, placement and adapter exceptions safely" do
    good = binding("alpha", "synthetic-alpha-secret")

    for model <- [
          Map.put(good, :provider, "unknown"),
          Map.put(good, :module, AlternateModel),
          Map.put(good, :config, %{"unknown" => true}),
          Map.put(good, :placement, %{budget_ms: 1}),
          Map.put(good, :provider, "raising"),
          Map.put(good, :credentials, %{"session" => %{}})
        ] do
      assert {:error, :invalid_agent_options} = Agent.start(node(), id: "bad", model: model)
    end

    assert {:error, :invalid_agent_options} =
             Agent.start(node(), id: "collection", model: good, models: [good])

    assert {:error, :invalid_node_configuration} =
             Beamlet.Node.configuration(
               roles: [:executor],
               profiles: %{
                 "old" => %{
                   type: :model,
                   module: AlternateModel,
                   settings: %{},
                   capability: "old"
                 }
               }
             )

    assert {:error, :invalid_node_configuration} =
             Beamlet.Node.configuration(
               roles: [:executor],
               model_providers: Map.new(1..33, &{"p#{&1}", AlternateModel})
             )

    registry = Map.new(1..32, &{"p#{&1}", AlternateModel})
    tool = %{type: :tool, module: Deterministic, settings: %{}, capability: "extra"}

    assert {:error, :invalid_node_configuration} =
             Beamlet.Node.configuration(
               roles: [:executor],
               model_providers: registry,
               profiles: %{"echo" => tool}
             )

    registry =
      Map.new(1..16, &{String.duplicate("p", 60) <> Integer.to_string(&1), AlternateModel})

    assert {:error, :invalid_node_configuration} =
             Beamlet.Node.configuration(
               roles: [:executor],
               model_providers: registry,
               limits: [report_bytes: 1024]
             )
  end

  test "delegation uses only explicit child binding" do
    {:ok, catalogue} = Catalogue.new([Deterministic.descriptor()])

    {:ok, parent} =
      Agent.start(node(), id: "parent", model: binding("alpha", "synthetic-alpha-secret"))

    :ok = Agent.subscribe(parent)
    child_binding = binding("beta", "synthetic-beta-secret")

    assert {:ok, _} =
             Agent.delegate(parent, [
               %{
                 authority: node(),
                 options: [
                   id: "explicit-child",
                   model: child_binding,
                   catalogue: catalogue,
                   tools: %{"echo" => %{id: "echo", capability: "echo"}}
                 ],
                 input: "child"
               }
             ])

    await_done(parent)

    for _ <- 1..2 do
      assert_receive {:alternate_invocation, invocation}
      assert invocation == Map.take(child_binding, [:config, :credentials])
    end

    assert :sys.get_state(parent.pid).model == binding("alpha", "synthetic-alpha-secret")
  end

  test "Caller separates credentials and config; Handler revalidates without Tool leakage" do
    model = binding("alpha", "synthetic-alpha-secret")
    request = %{"messages" => [%{"role" => "user", "content" => "x"}], "catalogue" => %{}}
    {:ok, op} = Caller.operation(model, request)
    assert op.credentials == model.credentials
    assert op.capabilities == ["model.provider:alternate"]
    refute Map.has_key?(op.payload, "credentials")
    {:ok, tool} = Caller.operation(%{id: "echo", capability: "echo"}, %{"text" => "x"})
    assert tool.credentials == %{}
    refute Map.has_key?(tool.payload, "config")

    context = %{
      credentials: model.credentials,
      settings: %{model_providers: %{"alternate" => AlternateModel}, profiles: %{}},
      progress: fn _ -> :ok end,
      cancelled?: fn -> false end
    }

    assert {:error, :invalid_request} =
             Handler.run(put_in(op.payload["config"], %{"dialect" => "bad"}), context)

    assert {:error, :invalid_profile} = Handler.run(tool.payload, context)
  end

  defp assert_clean(value) do
    text = inspect(value, limit: :infinity)
    refute text =~ "synthetic-alpha-secret"
    refute text =~ "synthetic-beta-secret"
    refute text =~ "dialect"
    refute text =~ "credentials"
  end

  defp await_done(ref) do
    receive do
      {:beamlet_agent, ^ref, seq, {:snapshot, s}} ->
        Agent.ack(ref, seq)
        assert_clean(s)
        if s.status == :done, do: :ok, else: await_done(ref)
    after
      3000 -> flunk("completion timeout")
    end
  end

  defp wait_retired(ref, tries \\ 100) do
    if map_size(:sys.get_state(ref.pid).owners) > 0 do
      assert tries > 0
      Process.sleep(10)
      wait_retired(ref, tries - 1)
    end
  end
end
