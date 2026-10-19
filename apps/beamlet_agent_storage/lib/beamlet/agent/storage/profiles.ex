defmodule Beamlet.Agent.Storage.Profiles do
  @moduledoc "可信代码定义的 agent-authority format3 清单，依次安装 foundation、Actions authority 与 Agent（迁移 1/100/300）。加载模块不启动 Repo；打开数据集不会补装或修复。

Trusted Agent authority installation descriptor."
  alias Beamlet.Actions.Storage.Profiles, as: Actions
  alias Beamlet.Storage.Installation

  @spec authority() :: Installation.t()
  @doc "返回 agent-authority format3 的有序组件/迁移清单（1/100/300）；仅描述安装，不启动 Repo。"
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
  @moduledoc "显式 Agent authority Repo；通过 Dataset 配合可信 descriptor 启动，加载模块不连接数据库。

Explicit opt-in Agent authority Repo."
  use Beamlet.Storage.Repo, adapter: :sqlite
end

defmodule Beamlet.Agent.Storage.PostgresAuthorityRepo do
  @moduledoc "显式 Agent authority Repo；通过 Dataset 配合可信 descriptor 启动，加载模块不连接数据库。

Explicit opt-in Agent authority Repo."
  use Beamlet.Storage.Repo, adapter: :postgres
end
