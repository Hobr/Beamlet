defmodule Beamlet.Actions.Storage.Profiles do
  @moduledoc "Explicit format3 Actions installations. Agent composition appends its component and migration."
  alias Beamlet.Storage.Installation
  def authority_component, do: %{name: "actions-authority", version: 1}
  def journal_component, do: %{name: "actions-journal", version: 1}

  def authority_migration,
    do: %{
      id: 100,
      component: "actions-authority",
      module: Beamlet.Actions.Storage.Migrations.AuthorityV1
    }

  def journal_migration,
    do: %{
      id: 200,
      component: "actions-journal",
      module: Beamlet.Actions.Storage.Migrations.JournalV1
    }

  def authority, do: descriptor("actions-authority", authority_component(), authority_migration())
  def journal, do: descriptor("actions-journal", journal_component(), journal_migration())

  defp descriptor(profile, component, migration) do
    %{
      profile: profile,
      format_version: 3,
      components: [Installation.foundation_component(), component],
      migrations: [Installation.foundation_migration(), migration]
    }
  end
end

defmodule Beamlet.Actions.Storage.SQLiteAuthorityRepo do
  @moduledoc false
  use Beamlet.Storage.Repo, adapter: :sqlite
end

defmodule Beamlet.Actions.Storage.PostgresAuthorityRepo do
  @moduledoc false
  use Beamlet.Storage.Repo, adapter: :postgres
end

defmodule Beamlet.Actions.Storage.ExecutorJournalRepo do
  @moduledoc false
  use Beamlet.Storage.Repo, adapter: :sqlite
end
