defmodule Beamlet.Actions.Storage.Profiles do
  @moduledoc "Explicit format3 Actions installations. Agent composition appends its component and migration."
  alias Beamlet.Storage.Installation
  @spec authority_component() :: Installation.component()
  def authority_component, do: %{name: "actions-authority", version: 1}
  @spec journal_component() :: Installation.component()
  def journal_component, do: %{name: "actions-journal", version: 1}

  @spec authority_migration() :: Installation.migration()
  def authority_migration,
    do: %{
      id: 100,
      component: "actions-authority",
      module: Beamlet.Actions.Storage.Migrations.AuthorityV1
    }

  @spec journal_migration() :: Installation.migration()
  def journal_migration,
    do: %{
      id: 200,
      component: "actions-journal",
      module: Beamlet.Actions.Storage.Migrations.JournalV1
    }

  @spec authority() :: Installation.t()
  def authority, do: descriptor("actions-authority", authority_component(), authority_migration())
  @spec journal() :: Installation.t()
  def journal, do: descriptor("actions-journal", journal_component(), journal_migration())

  @spec descriptor(String.t(), Installation.component(), Installation.migration()) ::
          Installation.t()
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
