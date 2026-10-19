defmodule Beamlet.Storage.Installation do
  @moduledoc """
  由上层可信代码提供的安装描述符。精确字段为 profile、format_version: 3、按序 components 和 migrations。foundation/version1/迁移ID1 必须在首位，每个组件必须有迁移；ID 唯一且递增，模块唯一并已编译。清单持久化模块身份而非源码哈希，已发布迁移不可改名、复用或修改实现；磁盘上的模块名不会用于选择代码。

  Trusted installation descriptor, supplied by the composing library.

  Exact fields: `profile` (stable string), `format_version` (3), `components`
  (ordered `%{name: string, version: positive_integer}` list), `migrations`
  (ordered `%{id: positive_integer, component: string, module: module}` list).
  IDs are globally unique within a profile and strictly increasing. Module names
  are persisted as identities; never rename/reuse an installed migration or ID.
  Modules must already be compiled trusted code; disk data never selects code.
  Every component has at least one migration. Foundation is first, version 1,
  migration 1. Upper layers compose all other components explicitly.
  """
  alias Beamlet.Storage.Migrations.FoundationV1

  @typedoc "组件名与正版本号；需由 validate 检查精确字段及顺序。

Trusted compiled installation plan; migration identities are stable persisted facts."
  @type component :: %{name: String.t(), version: pos_integer()}
  @typedoc "可信已编译迁移的稳定 ID、所属组件名和模块；ID 必须唯一递增。"
  @type migration :: %{id: pos_integer(), component: String.t(), module: module()}
  @typedoc "完整 format3 安装计划，顺序及精确字段由 validate 校验。"
  @type t :: %{
          profile: String.t(),
          format_version: 3,
          components: nonempty_list(component()),
          migrations: nonempty_list(migration())
        }
  @doc "返回必须位于组件列表首位的 foundation/version1 描述。"
  @spec foundation_component() :: component()
  def foundation_component, do: %{name: "foundation", version: 1}
  @doc "返回所有 format3 描述符必须以之开头的 foundation 迁移（ID1）。"
  @spec foundation_migration() :: migration()
  def foundation_migration, do: %{id: 1, component: "foundation", module: FoundationV1}

  @doc "校验描述符精确字段、组件归属、顺序及已编译迁移模块；有效返回 :ok，否则 invalid_data；不启动 Repo 或创建文件。"
  @spec validate(term()) :: :ok | {:error, :invalid_data}
  def validate(descriptor) do
    if valid?(descriptor), do: :ok, else: {:error, :invalid_data}
  rescue
    _ -> {:error, :invalid_data}
  end

  @spec valid?(term()) :: boolean()
  defp valid?(
         %{profile: profile, format_version: 3, components: components, migrations: migrations} =
           d
       ) do
    exact?(d, [:profile, :format_version, :components, :migrations]) and name?(profile) and
      is_list(components) and is_list(migrations) and
      valid_components?(components) and valid_migrations?(migrations) and
      Enum.sort(Enum.uniq(Enum.map(migrations, & &1.component))) ==
        Enum.sort(Enum.map(components, & &1.name))
  end

  defp valid?(_), do: false

  @spec valid_components?(list()) :: boolean()
  defp valid_components?(components) do
    List.first(components) == foundation_component() and
      Enum.all?(components, &component?/1) and unique?(Enum.map(components, & &1.name))
  end

  @spec valid_migrations?(list()) :: boolean()
  defp valid_migrations?(migrations) do
    List.first(migrations) == foundation_migration() and
      Enum.all?(migrations, &migration?/1) and unique?(Enum.map(migrations, & &1.module)) and
      ordered_ids?(Enum.map(migrations, & &1.id))
  end

  @spec component?(term()) :: boolean()
  defp component?(%{name: name, version: version} = c),
    do: exact?(c, [:name, :version]) and name?(name) and is_integer(version) and version > 0

  defp component?(_), do: false

  @spec migration?(term()) :: boolean()
  defp migration?(%{id: id, component: component, module: module} = m) do
    exact?(m, [:id, :component, :module]) and is_integer(id) and id > 0 and
      name?(component) and is_atom(module) and Code.ensure_loaded?(module) and
      function_exported?(module, :__migration__, 0)
  end

  defp migration?(_), do: false

  @spec name?(term()) :: boolean()
  defp name?(s),
    do: is_binary(s) and byte_size(s) in 1..128 and Regex.match?(~r/\A[a-z][a-z0-9_.-]*\z/, s)

  @spec exact?(map(), [atom()]) :: boolean()
  defp exact?(m, keys), do: Enum.sort(Map.keys(m)) == Enum.sort(keys)
  @spec unique?(list()) :: boolean()
  defp unique?(xs), do: Enum.uniq(xs) == xs
  @spec ordered_ids?([pos_integer()]) :: boolean()
  defp ordered_ids?(xs), do: unique?(xs) and Enum.sort(xs) == xs

  @doc "生成稳定安装清单字符串，包含按序组件版本和迁移 ID/组件/模块名；读取仅比较身份，不加载磁盘指定代码。

Stable JSON manifest; module identity is data only on read."
  @spec manifest(t()) :: binary()
  def manifest(d) do
    Jason.encode!(%{
      "components" => Enum.map(d.components, &%{"name" => &1.name, "version" => &1.version}),
      "migrations" =>
        Enum.map(
          d.migrations,
          &%{"id" => &1.id, "component" => &1.component, "module" => Atom.to_string(&1.module)}
        )
    })
  end
end
