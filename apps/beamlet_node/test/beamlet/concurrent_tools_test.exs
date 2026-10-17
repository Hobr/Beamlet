defmodule Beamlet.NodeConcurrentToolsTest do
  alias Beamlet.Node.TestBinding
  use ExUnit.Case
  alias Beamlet.Agent
  alias Beamlet.Harness.Catalogue
  alias Beamlet.Node.{TestBoot, TestModel, TestTool}

  test "several Agents join parallel Tools by original order despite reversed completions" do
    root = Path.join(System.tmp_dir!(), "beamlet_parallel_#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    File.write!(Path.join(root, "first"), "first")
    File.write!(Path.join(root, "second"), "second")
    on_exit(fn -> File.rm_rf!(root) end)

    profiles = %{
      "tree" => %{
        type: :tool,
        module: TestTool,
        settings: %{root: root, observer: self()},
        capability: "tree"
      }
    }

    start_supervised!(
      {Beamlet.Node,
       roles: [:authority, :executor],
       profiles: profiles,
       model_providers: %{"model" => TestModel},
       allowlist: %{model: [TestModel], tool: [TestTool]},
       pools: %{"native" => 8}}
    )

    TestBoot.barrier("model.provider:model")
    {:ok, catalogue} = Catalogue.new([TestTool.descriptor()])

    refs =
      for i <- 1..2 do
        {:ok, ref} =
          Agent.start(node(),
            id: "parallel#{i}",
            model: TestBinding.binding("model"),
            catalogue: catalogue,
            tools: %{"workspace_read" => %{id: "tree", capability: "tree"}}
          )

        Agent.subscribe(ref)
        Agent.input(ref, "parallel#{i}")
        ref
      end

    for _ <- refs, do: assert_receive({:model, _, _, _}, 3000)

    workers =
      for _ <- 1..4 do
        assert_receive {:tool, _, pid, path}, 3000
        {pid, path}
      end

    second = Enum.filter(workers, &(elem(&1, 1) == "second"))
    assert length(second) == 2

    Enum.each(second, fn {pid, _} ->
      monitor = Process.monitor(pid)
      send(pid, :release)
      assert_receive {:DOWN, ^monitor, _, _, _}, 3000
    end)

    Enum.each(workers, fn {pid, path} -> if path == "first", do: send(pid, :release) end)

    for _ <- refs do
      assert_receive {:model, _, _, history}, 3000
      observations = Enum.filter(history, &(&1["role"] == "tool"))
      assert Enum.map(observations, & &1["call_id"]) == ["call0", "call1"]
    end

    Enum.each(refs, fn ref ->
      assert_receive {:beamlet_agent, ^ref, _, {:snapshot, %{status: :done}}}, 3000
    end)
  end
end
