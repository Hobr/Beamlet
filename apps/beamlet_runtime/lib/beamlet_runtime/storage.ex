defmodule BeamletRuntime.Storage.Facts do
  @moduledoc "A committed, consistent Intent snapshot and its storage revision."
  @enforce_keys [:intent, :revision]
  defstruct @enforce_keys
end

defmodule BeamletRuntime.Storage.Commit do
  @moduledoc "Returned only after SQL commit, including rejected commands with durable expiry barriers."
  @enforce_keys [:facts, :reply, :events]
  defstruct @enforce_keys
end

defmodule BeamletRuntime.Storage.Error do
  @moduledoc "Storage failure, separate from domain rejection and business Outcome."
  @enforce_keys [:kind, :cause]
  defstruct @enforce_keys
end
