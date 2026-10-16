defmodule Beamlet.NodeDistributedTest do
  alias Beamlet.Harness.Catalogue
  alias Beamlet.Node.TestTool
  use ExUnit.Case
  @moduletag :distributed
  setup do
    unless Node.alive?(), do: flunk("named VM required")

    peers =
      for role <- [:interaction, :authority, :executor] do
        name = String.to_atom("beamlet_#{role}_#{System.unique_integer([:positive])}")
        paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

        {:ok, peer, remote} =
          :peer.start_link(%{
            name: name,
            connection: :standard_io,
            args:
              [
                ~c"+S",
                ~c"2:2",
                ~c"-kernel",
                ~c"prevent_overlapping_partitions",
                ~c"false",
                ~c"-setcookie",
                Atom.to_charlist(Node.get_cookie())
              ] ++ paths,
            wait_boot: 10_000,
            shutdown: 3000
          })

        Process.unlink(peer)
        on_exit(fn -> if Process.alive?(peer), do: :peer.stop(peer) end)
        {role, {peer, remote}}
      end
      |> Map.new()

    Enum.each(peers, fn {_, {peer, remote}} ->
      Enum.each(peers, fn {_, {_, other}} ->
        if other != remote, do: :peer.call(peer, Node, :connect, [other])
      end)
    end)

    root = Path.join(System.tmp_dir!(), "beamlet_native_#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    File.write!(Path.join(root, "first"), "first text")
    File.write!(Path.join(root, "second"), "second text")
    on_exit(fn -> File.rm_rf!(root) end)

    profiles = %{
      "held" => %{
        type: :model,
        module: Beamlet.Node.TestModel,
        settings: %{hold: true, observer: self()},
        capability: "held"
      },
      "model" => %{
        type: :model,
        module: Beamlet.Node.TestModel,
        settings: %{loop: true, observer: self()},
        capability: "model"
      },
      "workspace" => %{
        type: :tool,
        module: TestTool,
        settings: %{root: root, observer: self()},
        capability: "workspace",
        environment: "tree"
      }
    }

    Enum.each(peers, fn {role, {peer, _}} ->
      opts = [roles: [role], limits: [refresh_ms: 20, expiry_ms: 500]]

      opts =
        if role == :executor,
          do:
            opts ++
              [
                profiles: profiles,
                pools: %{"native" => 8},
                allowlist: %{model: [Beamlet.Node.TestModel], tool: [TestTool]}
              ],
          else: opts

      assert :ok = :peer.call(peer, Beamlet.Node.TestBoot, :boot, [opts])
    end)

    {bp, _} = peers.authority
    :ok = :peer.call(bp, Beamlet.Node.TestBoot, :barrier, ["model"])
    %{peers: peers}
  end

  test "three role VMs execute model and parallel workspace tools remotely in original order", %{
    peers: peers
  } do
    {ap, _} = peers.interaction
    {_, authority} = peers.authority
    {cp, executor} = peers.executor
    assert nil == :peer.call(cp, Process, :whereis, [Beamlet.Agent.Registry])
    {:ok, catalogue} = Catalogue.new([TestTool.descriptor()])

    opts = [
      id: "remote",
      model: %{id: "model", capability: "model"},
      catalogue: catalogue,
      tools: %{
        "workspace_read" => %{id: "workspace", capability: "workspace", environment: "tree"}
      }
    ]

    assert {:ok, ref} = :peer.call(ap, Beamlet.Agent, :start, [authority, opts])
    assert ref.authority == authority
    assert :ok = :peer.call(ap, Beamlet.Agent, :subscribe, [ref, self()])
    assert_receive {:beamlet_agent, ^ref, _, {:snapshot, %{status: :idle}}}
    assert {:ok, _} = :peer.call(ap, Beamlet.Agent, :input, [ref, "read"])
    assert_receive {:model, ^executor, _, _}, 3000
    assert_receive {:tool, ^executor, first, "first"}, 3000
    assert_receive {:tool, ^executor, second, "second"}, 3000
    send(second, :release)
    # The second worker's DOWN is a completion barrier; first remains blocked.
    monitor = Process.monitor(second)
    assert_receive {:DOWN, ^monitor, _, _, _}, 3000
    send(first, :release)
    assert_receive {:model, ^executor, _, messages}, 3000

    assert Enum.map(Enum.filter(messages, &(&1["role"] == "tool")), & &1["tool_call_id"]) == [
             "call0",
             "call1"
           ]

    assert_receive {:beamlet_agent, ^ref, _, {:snapshot, %{status: :done, final: final}}}, 3000
    assert final =~ "first text"
    assert final =~ "second text"

    assert {:ok, missing} =
             :peer.call(ap, Beamlet.Agent, :start, [
               authority,
               [id: "missing", model: %{id: "missing", capability: "absent"}]
             ])

    Beamlet.Agent.subscribe(missing)
    Beamlet.Agent.input(missing, "no fallback")
    assert_receive {:beamlet_agent, ^missing, _, {:snapshot, %{status: :error}}}, 3000
    refute_receive {:model, _, _, _}, 50

    wrong_workspace =
      opts
      |> Keyword.put(:id, "wrong-workspace")
      |> Keyword.put(
        :tools,
        %{
          "workspace_read" => %{
            id: "workspace",
            capability: "workspace",
            environment: "absent-tree"
          }
        }
      )

    {:ok, wrong} = :peer.call(ap, Beamlet.Agent, :start, [authority, wrong_workspace])
    Beamlet.Agent.subscribe(wrong)
    Beamlet.Agent.input(wrong, "no workspace fallback")
    assert_receive {:model, ^executor, _, _}, 3000
    assert_receive {:model, ^executor, _, history}, 3000
    observations = Enum.filter(history, &(&1["role"] == "tool"))
    assert length(observations) == 2
    assert Enum.all?(observations, &String.contains?(&1["content"], "no_target"))
    refute_receive {:tool, _, _, _}, 50
  end

  test "child authority disconnect is a correlated loss with owned cleanup and no recreation", %{
    peers: peers
  } do
    {ap, interaction} = peers.interaction
    {bp, authority} = peers.authority
    {_, executor} = peers.executor
    :ok = :peer.call(ap, Beamlet.Node.TestBoot, :authority, [])

    {:ok, parent} =
      :peer.call(ap, Beamlet.Agent, :start, [
        interaction,
        [id: "delegator", model: %{id: "model", capability: "model"}]
      ])

    Beamlet.Agent.subscribe(parent)

    spec = %{
      authority: authority,
      options: [id: "remote-child", model: %{id: "held", capability: "held"}],
      input: "hold"
    }

    assert {:ok, _} = Beamlet.Agent.delegate(parent, [spec])
    assert_receive {:model, ^executor, worker, _}, 3000
    monitor = Process.monitor(worker)
    assert {:ok, %{status: :waiting}} = Beamlet.Agent.snapshot(parent)
    assert true = :peer.call(ap, Node, :disconnect, [authority])
    :peer.call(bp, Node, :disconnect, [interaction])

    assert_receive {:beamlet_agent, ^parent, _,
                    {:snapshot, %{status: :done, final: [%{status: :error, value: :child_lost}]}}},
                   5000

    assert_receive {:DOWN, ^monitor, _, _, _}, 5000
    refute_receive {:model, ^executor, _, _}, 50
  end
end
