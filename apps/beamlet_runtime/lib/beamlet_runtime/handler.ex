defmodule BeamletRuntime.Handler do
  @moduledoc """
  Trusted, statically configured Operation and resource Adapter.

  identity/operations identify a release and compatible contracts. bind and
  validate_binding must be bounded local checks: no network, effects or credential
  bodies. Storage rechecks them under transaction protection; invocation rechecks
  actual resources outside SQL. validate_input/result enforce Operation schemas.

  invoke returns explicit contract evidence or uncertain; an exception, timeout or
  network error is never automatically Failure. A Pending binding must already
  contain durable completion correlation before invoke. query and verify_callback
  are optional authenticated evidence producers with stable Report identities.
  Configuration may contain runtime objects; bindings and reports may not.
  """
  alias Beamlet.{Execution, Intent, Report}
  alias BeamletRuntime.Grant

  @callback identity(term()) :: String.t()
  @callback operations(term()) :: [String.t()]
  @callback validate_input(Beamlet.Definition.t(), term()) :: :ok | {:error, atom()}
  @callback bind(Intent.t(), Execution.t(), term(), term()) :: {:ok, map()} | {:error, atom()}
  @callback validate_binding(Intent.t(), map(), term(), term()) :: :ok | {:error, atom()}
  @callback validate_result(String.t(), atom(), Beamlet.Value.t(), term()) ::
              :ok | {:error, atom()}
  @callback invoke(Grant.t(), term()) ::
              {:success | :failure | :pending, Beamlet.Value.t()} | {:uncertain, term()}
  @callback query(Intent.t(), Execution.t(), term()) :: {:ok, Report.t()} | {:error, term()}
  @callback verify_callback(Intent.t(), Execution.t(), term(), term()) ::
              {:ok, Report.t()} | {:error, term()}
  @optional_callbacks query: 3, verify_callback: 4
end
