defmodule Beamlet.Runtime.SharedSupervisor do
  @moduledoc "Opt-in node infrastructure. Restart invalidates all live references."
  use Supervisor

  alias Beamlet.Runtime.{
    Coordinators,
    Directory,
    ExecutionSupervisor,
    Groups,
    Limits,
    NodeEndpoint,
    Persistence
  }

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(opts) do
    limits = Limits.new(opts)
    opts = Keyword.put(opts, :persistence, Persistence.new(Keyword.get(opts, :persistence)))

    execution = Keyword.get(opts, :execution, false)
    unless is_boolean(execution), do: raise(ArgumentError, "execution must be boolean")
    execution_children = if execution, do: [{ExecutionSupervisor, {opts, limits}}], else: []

    children =
      [
        %{id: :pg, start: {:pg, :start_link, [Groups]}},
        {DynamicSupervisor,
         name: Coordinators, strategy: :one_for_one, max_children: limits.coordinators},
        {Directory, limits}
      ] ++ execution_children ++ [{NodeEndpoint, limits}]

    Supervisor.init(children, strategy: :one_for_all)
  end
end

defmodule Beamlet.Runtime.Limits do
  @moduledoc false
  def new(opts) do
    defaults = %{
      coordinators: 256,
      retention_ms: 30_000,
      refresh_ms: 1_000,
      expiry_ms: 5_000,
      admission_ms: 2_000,
      cancel_ms: 100,
      attempts: 512,
      progress_count: 256,
      progress_credit: 16,
      progress_rate: 20,
      operation_bytes: 262_144,
      result_bytes: 1_048_576,
      progress_bytes: 8192,
      report_bytes: 65_536
    }

    supplied = Keyword.get(opts, :limits, [])

    Enum.reduce(supplied, defaults, fn {key, value}, acc ->
      ceiling =
        if key in [:operation_bytes, :result_bytes, :progress_bytes, :report_bytes],
          do: defaults[key],
          else: 3_600_000

      minimum =
        if key in [:operation_bytes, :result_bytes, :progress_bytes, :report_bytes],
          do: 1024,
          else: 1

      unless Map.has_key?(acc, key) and is_integer(value) and value >= minimum and
               value <= ceiling,
             do: raise(ArgumentError, "invalid runtime limit")

      Map.put(acc, key, value)
    end)
  end
end
