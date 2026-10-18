defmodule Beamlet.Runtime.TestHandler do
  @moduledoc false
  @behaviour Beamlet.Actions.Handler
  def run(%{"mode" => "credentials"}, context) do
    # Explicit test-only observer; normal outputs below contain no invocation data.
    send(context.settings, {:credentials, node(), context.credentials})
    true = is_integer(context.remaining_ms)
    false = context.cancelled?.()
    :ok = context.progress.("working")
    {:ok, "done"}
  end

  def run(%{"mode" => "trap"}, context) do
    Process.flag(:trap_exit, true)
    run(%{"mode" => "hold"}, context)
  end

  def run(%{"mode" => "aux"}, context) do
    parent = self()

    spawn_link(fn ->
      assert_progress = context.progress.(String.duplicate("x", 1500))
      send(context.settings, {:large_progress, assert_progress})
      context.progress.("live")
      send(parent, :emitted)
    end)

    receive do
      :emitted -> send(context.settings, {:worker, self()})
    end

    receive do
      :release -> {:ok, "done"}
    end
  end

  def run(%{"mode" => "oversize"}, _), do: {:ok, String.duplicate("x", 1_048_576)}

  def run(%{"mode" => "hold"}, context) do
    send(context.settings, {:worker, self()})

    receive do
      :release -> {:ok, "released"}
    end
  end

  def run(%{"mode" => "progress"}, context) do
    Enum.each(1..300, fn i -> context.progress.(i) end)
    {:ok, "done"}
  end

  def run(payload, _), do: {:ok, %{"node" => Atom.to_string(node()), "echo" => payload}}
end

defmodule Beamlet.Runtime.TestPeer do
  @moduledoc false
  alias Beamlet.Actions.Operation
  alias Beamlet.Runtime.{Directory, SharedSupervisor}
  alias Beamlet.Storage.{Dataset, ExecutorJournalRepo}

  def boot(opts) do
    {:ok, pid} = SharedSupervisor.start_link(opts)
    Process.unlink(pid)
    :ok
  end

  def boot_durable(journal_opts, persistence, observer) do
    Application.ensure_all_started(:beamlet_storage)

    {:ok, repo} =
      Dataset.initialize(ExecutorJournalRepo, journal_opts)

    Process.unlink(repo)

    boot(
      execution: true,
      persistence: persistence,
      handlers: %{"durable" => {Beamlet.Runtime.TestHandler, observer}},
      limits: [refresh_ms: 10, expiry_ms: 1000]
    )
  end

  def operation_cap(bytes) do
    :sys.replace_state(Beamlet.Runtime.ExecutorGateway, fn state ->
      %{state | limits: %{state.limits | operation_bytes: bytes}}
    end)

    :ok
  end

  def barrier(kind, timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait(kind, deadline)
  end

  defp wait(kind, deadline) do
    {:ok, op} = Operation.new(kind: kind)

    case Directory.select(op) do
      {:ok, _, _} ->
        :ok

      :none ->
        if System.monotonic_time(:millisecond) >= deadline, do: raise("discovery timeout")

        receive do
        after
          10 -> wait(kind, deadline)
        end
    end
  end
end
