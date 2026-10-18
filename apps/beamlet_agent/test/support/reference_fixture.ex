Code.require_file("../../../beamlet_agent_storage/test/support/contract_fixture.ex", __DIR__)

defmodule Beamlet.Agent.ReferenceFixture do
  @moduledoc false
  import Kernel, except: [binding: 0]
  import ExUnit.Assertions
  alias Beamlet.Actions.Storage.ExecutorJournalRepo
  alias Beamlet.Actions.Storage.OperationRecords, as: ActionsOperations
  alias Beamlet.Actions.Storage.Profiles, as: ActionsProfiles
  alias Beamlet.Agent.ContextBuilder
  alias Beamlet.Agent.Durable
  alias Beamlet.Agent.Integration.Caller
  alias Beamlet.Agent.Storage.ContractFixture
  alias Beamlet.Harness.Catalogue
  alias Beamlet.Harness.Tools.Deterministic
  alias Beamlet.Storage.Dataset

  def open do
    adapter =
      if System.get_env("BEAMLET_AGENT_TEST_ADAPTER") == "postgres", do: :postgres, else: :sqlite

    f = ContractFixture.open(adapter)
    dir = Path.join(System.tmp_dir!(), "beamlet-d-#{uuid()}")
    File.mkdir_p!(dir)

    {:ok, _} =
      Dataset.initialize(ExecutorJournalRepo,
        descriptor: ActionsProfiles.journal(),
        database: Path.join(dir, "j.db"),
        peer_database: Path.join(dir, "a.db"),
        dataset_id: uuid()
      )

    {:ok, d} =
      Durable.open(f.repo, %{
        agent_id: uuid(),
        authority_id: f.authority_id,
        command_id: uuid(),
        definition: %{"version" => 1}
      })

    {:ok, d} =
      Durable.with_runtime(d, %{
        authority_repo: f.repo,
        journal_repo: ExecutorJournalRepo,
        executor_id: uuid(),
        executor_boot_id: uuid()
      })

    %{durable: d, dir: dir, fixture: f}
  end

  def close(ctx) do
    stop_journal()
    ContractFixture.close(ctx.fixture)
    File.rm_rf!(ctx.dir)
  end

  defp stop_journal do
    if pid = Process.whereis(ExecutorJournalRepo) do
      monitor = Process.monitor(pid)

      try do
        Supervisor.stop(pid)
      catch
        :exit, _ -> :ok
      end

      receive do
        {:DOWN, ^monitor, :process, ^pid, _} -> :ok
      after
        5000 -> flunk("journal did not stop")
      end
    end
  end

  def uuid, do: Ecto.UUID.generate()
  def locator(d), do: %{repo: d.repo, agent_id: d.agent_id, runtime: d.runtime}

  def binding,
    do: %{
      provider: "deterministic",
      config: %{"reply" => %{"kind" => "text", "content" => "unused", "calls" => []}}
    }

  def catalogue do
    {:ok, c} = Catalogue.new([Deterministic.descriptor()])
    c
  end

  def input(d, text \\ "hello") do
    {:ok, next} = Durable.accept_input(d, %{text: text, turn_id: uuid(), command_id: uuid()})
    next
  end

  def model(d, value, position \\ "completed") do
    {:ok, built} = Durable.context(d, catalogue())
    {:ok, op} = Caller.operation(binding(), built.request, 262_144)
    {:ok, d, [member]} = Durable.prepare(d, [%{operation: op}], "model", built.sources)
    {:ok, _} = accept(d, member, "ok", value)
    {:ok, d} = Durable.consume(d, [member["operation_id"]], position)
    {d, member}
  end

  def accept(d, member, status, value) do
    ActionsOperations.accept_result(d.repo, %{
      operation_id: member["operation_id"],
      expected_version: 0,
      result: %{"status" => status, "value" => value, "reason" => nil}
    })
  end

  def complete(d) do
    calls =
      for n <- 1..2,
          do: %{"id" => "call-#{n}", "name" => "echo", "arguments" => %{"text" => "#{n}"}}

    d = input(d)

    {d, model} =
      model(d, %{"kind" => "tool_calls", "content" => nil, "calls" => calls}, "reply_recorded")

    members =
      Enum.map(calls, fn c ->
        {:ok, op} =
          Caller.operation(%{id: "echo-profile", capability: "echo"}, c["arguments"], 262_144)

        %{id: c["id"], operation: op}
      end)

    {:ok, d, tools} = Durable.prepare(d, members, "tool", [])

    for member <- Enum.reverse(tools),
        do: assert({:ok, _} = accept(d, member, "ok", %{"text" => "done"}))

    {:ok, d} = Durable.consume(d, Enum.map(tools, & &1["operation_id"]), "await_model_result")
    {d, last} = model(d, %{"kind" => "text", "content" => "finished", "calls" => []})
    assert {:ok, messages} = ContextBuilder.materialize(d.repo, d.control)
    assert length(messages) == 5
    {d, [model | tools] ++ [last]}
  end

  def fork(d, opts \\ []) do
    source = Keyword.get(opts, :source, %{environment: :confirmed_stopped})

    Beamlet.Agent.fork(
      Map.put(locator(d), :source, source),
      d.control["through_seq"],
      d.version,
      Keyword.get_lazy(opts, :command, &uuid/0)
    )
  end
end
