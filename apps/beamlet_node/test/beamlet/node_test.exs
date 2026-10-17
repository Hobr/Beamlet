defmodule Beamlet.NodeTest do
  alias Beamlet.Harness.Catalogue
  alias Beamlet.Harness.Tools.WorkspaceRead
  alias Beamlet.Runtime.Directory
  use ExUnit.Case

  test "role validation and opt-in executor composition" do
    for roles <- [
          [:interaction],
          [:authority],
          [:executor],
          [:interaction, :authority],
          [:interaction, :executor],
          [:authority, :executor],
          [:interaction, :authority, :executor]
        ] do
      assert {:ok, children} = Beamlet.Node.configuration(roles: roles)

      assert Enum.any?(
               children,
               &(match?({Beamlet.Runtime, _}, &1) or match?({Beamlet.Node.Runtime, _}, &1))
             )

      assert Enum.any?(children, &match?({Beamlet.Agent.AuthoritySupervisor, _}, &1)) ==
               :authority in roles
    end

    assert {:error, :invalid_node_configuration} = Beamlet.Node.configuration(roles: [:unknown])
  end

  test "smaller Runtime executable ceiling rejects before scheduling" do
    start_supervised!({Beamlet.Node, roles: [:authority], limits: [operation_bytes: 1024]})

    {:ok, ref} =
      Beamlet.Agent.start(node(),
        id: "small",
        model: %{
          provider: "deterministic",
          config: %{"reply" => %{"kind" => "text", "content" => "ok", "calls" => []}}
        }
      )

    assert {:error, :invalid_or_oversize_input} =
             Beamlet.Agent.input(ref, String.duplicate("x", 2000))

    assert {:ok, %{status: :idle, turn: nil}} = Beamlet.Agent.snapshot(ref)
    assert :sys.get_state(ref.pid).messages == []
  end

  test "authority can resolve opaque routes and catalogue without native secrets or roots" do
    {:ok, catalogue} =
      Catalogue.new([WorkspaceRead.descriptor()])

    route = %{id: "public-model", capability: "model", claims: %{"native" => 1}}

    start_supervised!(
      {Beamlet.Node,
       roles: [:authority], routes: %{"public-model" => route}, catalogue: catalogue}
    )

    assert {:ok, ^route} = Beamlet.Node.profile("public-model")
    assert {:ok, ^catalogue} = Beamlet.Node.catalogue()
    assert nil == Process.whereis(Beamlet.Node.Provider)
    assert nil == Process.whereis(Beamlet.Runtime.ExecutorGateway)
    assert :error = Beamlet.Node.profile("missing")
  end

  test "local native model goes through Runtime gateway" do
    reply = %{"kind" => "text", "content" => "answer", "calls" => []}

    profiles = %{}

    start_supervised!(
      {Beamlet.Node,
       roles: [:authority, :executor],
       profiles: profiles,
       model_providers: %{"fixture" => Beamlet.Harness.Models.Deterministic}}
    )

    # Directory queries asynchronously; explicit endpoint discovery barrier.
    wait_ready(100)

    assert {:ok, ref} =
             Beamlet.Agent.start(node(),
               id: "local",
               model: %{provider: "fixture", config: %{"reply" => reply}}
             )

    assert :ok = Beamlet.Agent.subscribe(ref)
    assert_receive {:beamlet_agent, ^ref, seq, {:snapshot, %{status: :idle}}}
    Beamlet.Agent.ack(ref, seq)
    assert {:ok, _} = Beamlet.Agent.input(ref, "hello")
    assert_receive {:beamlet_agent, ^ref, _, {:snapshot, %{status: :running}}}
    assert_receive {:beamlet_agent, ^ref, _, {:snapshot, %{status: :done, final: "answer"}}}, 3000
  end

  defp wait_ready(0), do: flunk("executor discovery did not become ready")

  defp wait_ready(n) do
    if Enum.any?(Directory.snapshots(), fn {_, r} -> r.execution_ready end) do
      :ok
    else
      receive do
      after
        10 -> wait_ready(n - 1)
      end
    end
  end
end
