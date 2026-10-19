defmodule Beamlet.Actions.Storage.Profiles do
  @moduledoc "可信代码定义的 format3 Actions 安装描述符。authority 为 foundation+actions-authority，journal 为 foundation+actions-journal；仅返回清单，加载模块不会启动 Repo 或安装表。

Explicit format3 Actions installations. Agent composition appends its component and migration."
  alias Beamlet.Storage.Installation
  @spec authority_component() :: Installation.component()
  @doc "返回可信 actions-authority version1 组件；仅描述安装，不执行迁移或启动 Repo。"
  def authority_component, do: %{name: "actions-authority", version: 1}
  @spec journal_component() :: Installation.component()
  @doc "返回可信 actions-journal version1 组件；仅描述安装，不执行迁移或启动 Repo。"
  def journal_component, do: %{name: "actions-journal", version: 1}

  @spec authority_migration() :: Installation.migration()
  @doc "返回可信 ID100 AuthorityV1 迁移；仅描述安装，不执行迁移或启动 Repo。"
  def authority_migration,
    do: %{
      id: 100,
      component: "actions-authority",
      module: Beamlet.Actions.Storage.Migrations.AuthorityV1
    }

  @spec journal_migration() :: Installation.migration()
  @doc "返回可信 ID200 JournalV1 迁移；仅描述安装，不执行迁移或启动 Repo。"
  def journal_migration,
    do: %{
      id: 200,
      component: "actions-journal",
      module: Beamlet.Actions.Storage.Migrations.JournalV1
    }

  @spec authority() :: Installation.t()
  @doc "返回可信 actions-authority format3 清单（迁移 1/100）；仅描述安装，不执行迁移或启动 Repo。"
  def authority, do: descriptor("actions-authority", authority_component(), authority_migration())
  @spec journal() :: Installation.t()
  @doc "返回可信 actions-journal format3 清单（迁移 1/200）；仅描述安装，不执行迁移或启动 Repo。"
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
