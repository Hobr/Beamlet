defmodule Beamlet.Agent.Storage.Profiles do
  @moduledoc "Trusted Agent authority installation descriptor."
  alias Beamlet.Actions.Storage.Profiles, as: Actions
  alias Beamlet.Storage.Installation

  def authority do
    %{
      profile: "agent-authority",
      format_version: 3,
      components: [
        Installation.foundation_component(),
        Actions.authority_component(),
        %{name: "agent", version: 1}
      ],
      migrations: [
        Installation.foundation_migration(),
        Actions.authority_migration(),
        %{id: 300, component: "agent", module: Beamlet.Agent.Storage.Migrations.AgentV1}
      ]
    }
  end
end

defmodule Beamlet.Agent.Storage.SQLiteAuthorityRepo do
  @moduledoc "Explicit opt-in Agent authority Repo."
  use Beamlet.Storage.Repo, adapter: :sqlite
end

defmodule Beamlet.Agent.Storage.PostgresAuthorityRepo do
  @moduledoc "Explicit opt-in Agent authority Repo."
  use Beamlet.Storage.Repo, adapter: :postgres
end
