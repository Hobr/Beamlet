defmodule Beamlet.Server.E2EModel do
  @moduledoc false
  @behaviour Beamlet.Harness.Model
  alias Beamlet.Harness.Models.Deterministic

  @impl true
  defdelegate validate_invocation(invocation), to: Deterministic

  @impl true
  def complete(request, _invocation, _context \\ %Beamlet.Harness.Context{}) do
    send(:beamlet_e2e_sink, {:model_call, self()})

    if Enum.any?(request.messages, &(&1["role"] == "tool")) do
      {:ok, %{kind: :text, content: "e2e finished", calls: []}}
    else
      {:ok,
       %{
         kind: :tool_calls,
         content: nil,
         calls: [%{id: "call-e2e-1", name: "echo", arguments: %{"text" => "e2e-marker"}}]
       }}
    end
  end
end

defmodule Beamlet.Server.DurableEndToEndTest do
  @moduledoc """
  Stage F end-to-end path over real SQLite files: explicit operator migration, one
  durable operation through the Agent and Runtime with a deterministic model and
  Tool, a host restart, a paused restore that dispatches nothing, an explicit
  continuation, bounded trace export, verification and a fork of the safe
  checkpoint.

  The ordinary test restarts the host wiring inside one VM. `scripts/deployment/
  durable-e2e.sh` runs the same phases as two separate OS processes
  (`:durable_e2e_phase1` / `:durable_e2e_phase2` tags), which is the restart
  evidence.
  """
  use ExUnit.Case, async: false

  alias Beamlet.Agent
  alias Beamlet.Agent.AuthoritySupervisor
  alias Beamlet.Agent.{Durable, TraceExport}
  alias Beamlet.Harness.{Catalogue, Model}
  alias Beamlet.Harness.Tools.Deterministic
  alias Beamlet.Runtime.{Directory, Persistence, SharedSupervisor}

  alias Beamlet.Storage.{
    Admission,
    AgentRecords,
    ExecutorJournalRepo,
    Host,
    Operator,
    SQLiteAuthorityRepo
  }

  @tools %{"echo" => %{id: "echo-profile", capability: "echo"}}

  setup do
    # The two-phase run shares one directory between two OS processes; the ordinary
    # test gets its own isolated directory and removes it.
    configured = System.get_env("DURABLE_E2E_DIR")

    dir =
      configured ||
        Path.join(
          System.tmp_dir!(),
          "beamlet-e2e-#{System.system_time(:microsecond)}-#{System.unique_integer([:positive])}"
        )

    File.mkdir_p!(dir)
    Process.register(self(), :beamlet_e2e_sink)

    on_exit(fn ->
      stop_wiring()
      if configured == nil, do: File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  test "one durable turn survives a restart, restores paused, continues, exports and forks",
       ctx do
    first = phase_one(ctx.dir)
    assert first.tool_results == 1
    assert first.messages >= 3
    assert first.boundary_checkpoint_id != first.checkpoint_id
    stop_wiring()

    second = phase_two(ctx.dir, first)
    assert second.model_calls_before_continue == 0
    assert second.export_events > first.events
    assert second.verified_events == second.export_events
    assert second.fork_agent_id != first.agent_id
  end

  @tag :durable_e2e_phase1
  test "phase one: migrate and commit one durable operation", ctx do
    if System.get_env("DURABLE_E2E_DIR"), do: :ok
    state = phase_one(ctx.dir)
    File.write!(Path.join(ctx.dir, "state.term"), :erlang.term_to_binary(state))
  end

  @tag :durable_e2e_phase2
  test "phase two: restart, paused restore, explicit continue, export and fork", ctx do
    state = ctx.dir |> Path.join("state.term") |> File.read!() |> :erlang.binary_to_term([:safe])
    phase_two(ctx.dir, state)
  end

  ## Phase one: operator migration and one durable operation

  defp phase_one(dir) do
    storage = storage(dir)
    authority_id = read_or_put(dir, :authority_id)

    assert {:ok, %{authority: :installed, journal: :installed}} =
             Operator.initialize([:authority, :executor], storage)

    boot_wiring(storage, authority_id)
    {:ok, runtime} = Host.runtime()
    assert :admitted = Admission.status()

    durable = durable(runtime, authority_id)

    {:ok, %{"head_checkpoint" => initial}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    {:ok, ref} = Agent.start(node(), agent_options(durable))
    Process.put(:e2e_ref, ref)
    {:ok, _view} = Agent.input(ref, "run the deterministic tool", uuid())
    wait_for_turn(durable)

    {:ok, %{"agent" => agent, "head_checkpoint" => head}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    {:ok, %{"events" => events}} =
      AgentRecords.history_page(SQLiteAuthorityRepo, durable.agent_id, limit: 500)

    %{
      storage: storage,
      agent_id: durable.agent_id,
      authority_id: authority_id,
      version: agent["lock_version"],
      checkpoint_id: head["id"],
      boundary_checkpoint_id: initial["id"],
      messages: length(head["data"]["messages"]),
      tool_results: Enum.count(events, &(&1["type"] == "result.consumed")),
      events: length(events)
    }
  end

  ## Phase two: restart, paused restore, explicit continuation, export, fork

  defp phase_two(dir, state) do
    boot_wiring(state.storage, state.authority_id)
    {:ok, runtime} = Host.runtime()

    # A restarted host re-probes admission instead of trusting the previous boot.
    assert :admitted = Admission.status()
    drain_model_calls()

    locator =
      %{
        repo: SQLiteAuthorityRepo,
        agent_id: state.agent_id,
        model: model_binding(),
        tools: @tools,
        catalogue: catalogue(),
        runtime: runtime
      }

    {:ok, ref} = Agent.restore(locator, state.version, uuid())
    assert drain_model_calls() == 0
    # A restored instance stays paused: no model, Tool or network work happens until
    # the operator continues it explicitly. The continuation is one recorded
    # decision that replays the stored reply instead of re-requesting the model.
    model_calls_before_continue = drain_model_calls()
    assert model_calls_before_continue == 0
    # The restore itself advanced the stored version, so continue from that one.
    {:ok, %{"agent" => %{"lock_version" => version}}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, state.agent_id)

    assert {:ok, %{status: :done}} = Agent.continue(ref, version, %{}, uuid())
    step("restored instance becomes idle", fn -> wait_for_idle(ref) end)

    # Explicit continuation after the paused restore: a new durable turn.
    assert drain_model_calls() == 0
    {:ok, _view} = Agent.input(ref, "continue after restore", uuid())

    durable = %Durable{
      repo: SQLiteAuthorityRepo,
      authority_id: state.authority_id,
      agent_id: state.agent_id
    }

    step("continued turn completes", fn -> wait_for_turn(durable) end)

    {:ok, %{"head_checkpoint" => head}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, state.agent_id)

    export_dir = Path.join(dir, "export")
    {:ok, manifest} = Agent.export(locator, %{agent_id: state.agent_id}, %{dir: export_dir})
    {:ok, verified} = TraceExport.verify(export_dir)
    assert verified["events"] == manifest["counts"]["events"]
    assert verified["checkpoints"] == manifest["counts"]["checkpoints"]

    # Fork the safe checkpoint of the completed turn, then verify its own export.
    Agent.close(ref)
    wait_until(fn -> Agent.lookup(node(), state.agent_id) == {:error, :not_found} end)

    # The fork copies the source's last safe boundary (an `await_input` checkpoint).
    # A completed turn rests at `reply_recorded`, whose stored reply is pending
    # state: forking it is refused instead of copying an undecided boundary.
    source = Map.put(locator, :source, %{freeze: :frozen, environment: :confirmed_stopped})

    {:ok, %{"agent" => %{"lock_version" => source_version}}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, state.agent_id)

    assert {:error, :unsafe_checkpoint} =
             Agent.fork(source, state.checkpoint_id, source_version, uuid())

    fork_dir = Path.join(dir, "fork")
    {:ok, fork} = Agent.fork(source, state.boundary_checkpoint_id, source_version, uuid())

    {:ok, %{"events" => fork_events}} =
      AgentRecords.history_page(SQLiteAuthorityRepo, fork.agent_id, limit: 500)

    {:ok, fork_manifest} =
      Agent.export(
        %{repo: SQLiteAuthorityRepo, agent_id: fork.agent_id},
        %{agent_id: fork.agent_id},
        %{dir: fork_dir}
      )

    {:ok, fork_verified} = TraceExport.verify(fork_dir)
    assert fork_verified["events"] == fork_manifest["counts"]["events"]
    assert Enum.any?(fork_events, &(&1["type"] == "agent.forked"))

    assert Enum.count(fork_events, &(&1["type"] == "context.inherited")) ==
             fork.copied["messages"]

    %{
      model_calls_before_continue: model_calls_before_continue,
      export_events: manifest["counts"]["events"],
      export_messages: length(head["data"]["messages"]),
      verified_events: verified["events"],
      fork_agent_id: fork.agent_id
    }
  end

  ## Wiring

  defp boot_wiring(storage, authority_id) do
    {:ok, settings} = Host.configuration([:authority, :executor], storage)
    {:ok, _} = Host.start_link(storage: settings, name: Host)
    {:ok, _} = AuthoritySupervisor.start_link(model_providers: providers())

    # The host owns this boot's executor identity: the Runtime and the Agent's
    # durable wiring must use the same boot id or evidence writes are refused.
    {:ok, host_runtime} = Host.runtime()

    persistence =
      Persistence.new(
        authority_repo: host_runtime.authority_repo,
        journal_repo: host_runtime.journal_repo,
        authority_id: authority_id,
        executor_id: host_runtime.executor_id,
        executor_boot_id: host_runtime.executor_boot_id
      )

    settings_map = %{
      model_providers: providers(),
      profiles: %{
        "echo-profile" => %{
          type: :tool,
          module: Beamlet.Harness.Tools.Deterministic,
          settings: %{}
        }
      }
    }

    {:ok, _} =
      SharedSupervisor.start_link(
        execution: true,
        handlers: %{"agent.native" => {Beamlet.Agent.Integration.Handler, settings_map}},
        capabilities: ["model.provider:e2e", "echo"],
        profiles: settings_map.profiles,
        model_providers: providers(),
        pools: %{"cpu" => 1},
        persistence: persistence,
        limits: [
          refresh_ms: 10,
          expiry_ms: 300,
          retention_ms: 1000,
          cancel_ms: 50,
          admission_ms: 500
        ]
      )

    wait_until(fn -> ready?() end)
  end

  defp durable(runtime, authority_id) do
    {:ok, durable} =
      Durable.open(SQLiteAuthorityRepo, %{
        agent_id: uuid(),
        authority_id: authority_id,
        alias: "e2e#{System.unique_integer([:positive])}",
        definition: definition(),
        command_id: uuid()
      })

    {:ok, durable} = Durable.with_runtime(durable, runtime)
    durable
  end

  defp agent_options(durable) do
    [
      id: durable.agent_id,
      model: model_binding(),
      tools: @tools,
      catalogue: catalogue(),
      durable: durable
    ]
  end

  # The deterministic adapter validates the invocation shape; the E2E model itself
  # decides the reply so the turn is reproducible without a provider.
  defp model_binding do
    %{
      provider: "e2e",
      config: %{"reply" => %{"kind" => "text", "content" => "unused", "calls" => []}}
    }
  end

  defp providers do
    Map.merge(Model.default_providers(), %{"e2e" => Beamlet.Server.E2EModel})
  end

  defp definition do
    %{
      "schema_version" => 1,
      "model" => %{
        "provider" => "e2e",
        "config" => %{"reply" => %{"kind" => "text", "content" => "unused", "calls" => []}}
      },
      "tools" => %{"echo" => %{"profile" => "echo-profile"}}
    }
  end

  defp catalogue do
    {:ok, catalogue} = Catalogue.new([Deterministic.descriptor()])
    catalogue
  end

  defp storage(dir) do
    [
      adapter: :sqlite,
      database: Path.join(dir, "authority.db"),
      dataset_id: read_or_put(dir, :dataset_id),
      journal: [
        database: Path.join(dir, "journal.db"),
        dataset_id: read_or_put(dir, :journal_dataset_id)
      ],
      executor_id: read_or_put(dir, :executor_id)
    ]
  end

  # Dataset identities are operator-owned and must survive a restart: a second
  # process re-reads them from the deployment, never generates new ones.
  defp read_or_put(dir, key) do
    path = Path.join(dir, "id-#{key}")

    value =
      case File.read(path) do
        {:ok, value} -> value
        {:error, _} -> Ecto.UUID.generate()
      end

    File.write!(path, value)
    value
  end

  defp stop_wiring do
    for name <- [Beamlet.Runtime.SharedSupervisor, Beamlet.Agent.AuthoritySupervisor, Host] do
      try do
        case Process.whereis(name) do
          nil -> :ok
          pid -> Supervisor.stop(pid, :normal, 5000)
        end
      catch
        _, _ -> :ok
      end
    end

    for repo <- [SQLiteAuthorityRepo, ExecutorJournalRepo] do
      try do
        if Process.whereis(repo), do: repo.stop()
      catch
        _, _ -> :ok
      end
    end
  end

  ## Waiting helpers

  # A completed durable turn rests at `reply_recorded` (or `await_input` when the
  # reply needed no Tool work); both are positions an operator can restore into.
  defp step(label, fun) do
    fun.()
  rescue
    error ->
      reraise RuntimeError.exception("#{label}: #{Exception.message(error)}"), __STACKTRACE__
  end

  defp wait_for_turn(durable) do
    wait_until(fn ->
      case AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id) do
        {:ok, %{"head_checkpoint" => head}} ->
          continuation = get_in(head, ["data", "continuation"])

          continuation in ["reply_recorded", "await_input"] and
            Enum.any?(head["data"]["messages"], &(&1["role"] == "tool"))

        _ ->
          false
      end
    end)
  end

  defp wait_for_idle(ref) do
    wait_until(fn ->
      case Agent.snapshot(ref) do
        {:ok, %{status: status}} -> status in [:idle, :done]
        _ -> false
      end
    end)
  end

  defp ready? do
    Enum.any?(Directory.snapshots(), fn {_node, report} ->
      "echo" in report.capabilities
    end)
  rescue
    _ -> false
  end

  defp drain_model_calls(count \\ 0) do
    receive do
      {:model_call, _pid} -> drain_model_calls(count + 1)
    after
      100 -> count
    end
  end

  defp wait_until(fun, remaining \\ 400)

  defp wait_until(fun, remaining) when remaining > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      wait_until(fun, remaining - 1)
    end
  end

  defp wait_until(_fun, 0), do: flunk("condition not reached in time")

  defp uuid, do: Ecto.UUID.generate()
end
