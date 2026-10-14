defmodule BeamletRuntime.Object.Repo do
  @moduledoc false
  use Ecto.Repo, otp_app: :beamlet_runtime, adapter: Ecto.Adapters.SQLite3
end
