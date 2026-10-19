defmodule Beamlet.Storage.Installation do
  @moduledoc """
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

  @typedoc "Trusted compiled installation plan; migration identities are stable persisted facts."
  @type component :: %{name: String.t(), version: pos_integer()}
  @type migration :: %{id: pos_integer(), component: String.t(), module: module()}
  @type t :: %{
          profile: String.t(),
          format_version: 3,
          components: nonempty_list(component()),
          migrations: nonempty_list(migration())
        }
  @spec foundation_component() :: component()
  def foundation_component, do: %{name: "foundation", version: 1}
  @spec foundation_migration() :: migration()
  def foundation_migration, do: %{id: 1, component: "foundation", module: FoundationV1}

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

  @doc "Stable JSON manifest; module identity is data only on read."
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
