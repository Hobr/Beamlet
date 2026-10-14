defmodule Beamlet.Agent.Caller.Repo do
  @moduledoc false
  use Ecto.Repo, otp_app: :beamlet_agent, adapter: Ecto.Adapters.SQLite3
end
