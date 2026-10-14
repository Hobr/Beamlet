defmodule BeamletRuntime.Storage.SQLite.Repo do
  @moduledoc "Ecto Repo used by the SQLite Adapter; dynamic repos isolate callers without serializing commands in a process."
  use Ecto.Repo, otp_app: :beamlet_runtime, adapter: Ecto.Adapters.SQLite3
end
