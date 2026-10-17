defmodule Beamlet.Actions.OperationRef do
  @moduledoc "Ephemeral coordinator address; never persisted or replayed."
  @enforce_keys [:id, :pid]
  defstruct [:id, :pid]
  @type t :: %__MODULE__{id: binary(), pid: pid()}
end

defmodule Beamlet.Actions.ExecutionHandle do
  @moduledoc "An admitted worker identity, distinct from the pre-admission attempt."
  @enforce_keys [:id, :gateway, :incarnation]
  defstruct [:id, :gateway, :incarnation]
  @type t :: %__MODULE__{id: binary(), gateway: pid(), incarnation: reference()}
end

defmodule Beamlet.Actions.Execution do
  @moduledoc "One attempt; handle remains nil until admission is observed."
  defstruct [
    :operation_id,
    :attempt_id,
    :endpoint,
    :incarnation,
    :handle,
    state: :awaiting_admission
  ]

  @type t :: %__MODULE__{
          operation_id: binary(),
          attempt_id: binary(),
          endpoint: pid(),
          incarnation: reference(),
          handle: Beamlet.Actions.ExecutionHandle.t() | nil,
          state: :awaiting_admission | :running | :completed | :uncertain
        }
end

defmodule Beamlet.Actions.Result do
  @moduledoc "Single bounded terminal observation. Uncertainty never implies remote termination."
  defstruct [:operation_id, :execution_id, :status, :reason, :value, :source, metadata: %{}]

  @type t :: %__MODULE__{
          operation_id: binary(),
          execution_id: binary() | nil,
          status: :ok | :error | :cancelled | :deadline | :uncertain,
          reason: term(),
          value: term(),
          source: :coordinator | :execution,
          metadata: map()
        }

  def valid?(%__MODULE__{} = result) do
    identity?(result) and is_map(result.metadata) and not is_struct(result.metadata) and
      result.status in [:ok, :error, :cancelled, :deadline, :uncertain] and
      result.source in [:coordinator, :execution] and
      Beamlet.Actions.bounded?(Map.from_struct(result), 1_048_576) and
      :erlang.external_size(result) <= 1_048_576
  end

  def valid?(_), do: false

  defp identity?(result) do
    id?(result.operation_id) and
      (is_nil(result.execution_id) or id?(result.execution_id)) and
      (result.source != :execution or id?(result.execution_id))
  end

  defp id?(id), do: is_binary(id) and byte_size(id) in 1..128
end

defmodule Beamlet.Actions.Handler do
  @moduledoc """
  Executor-local handler. Return {:ok, data} or {:error, safe_reason}.

  Context contains local `settings`, invocation `credentials` (default `%{}`),
  `remaining_ms`, and `progress`/`cancelled?` callbacks. Credentials are generic
  data and must not be copied into ordinary outputs or diagnostics.
  """
  @callback run(term(), map()) :: {:ok, term()} | {:error, term()}
end
