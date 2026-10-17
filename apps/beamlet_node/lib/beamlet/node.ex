defmodule Beamlet.Node do
  alias Beamlet.Harness.Model
  alias Beamlet.Runtime.Limits
  alias Beamlet.Runtime.Report
  @moduledoc "Trusted opt-in role composition. Default umbrella boot starts no roles."
  use Supervisor
  alias Beamlet.Agent.Integration.{Caller, Handler}
  alias Beamlet.Harness.Catalogue
  alias Beamlet.Node.Routes
  @tools [Beamlet.Harness.Tools.Deterministic, Beamlet.Harness.Tools.WorkspaceRead]

  def profile(id), do: GenServer.call(Routes, {:profile, id})
  def catalogue, do: GenServer.call(Routes, :catalogue)
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(opts) do
    case configuration(opts) do
      {:ok, children} -> Supervisor.init(children, strategy: :one_for_all)
      {:error, reason} -> raise ArgumentError, Atom.to_string(reason)
    end
  end

  def configuration(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: configure(opts), else: {:error, :invalid_node_configuration}
  end

  def configuration(_), do: {:error, :invalid_node_configuration}

  defp configure(opts) do
    roles = Keyword.get(opts, :roles, [])
    profiles = Keyword.get(opts, :profiles, %{})
    providers = Keyword.get(opts, :providers, [])
    models = Keyword.get(opts, :model_providers, Model.default_providers())
    allowlist = Keyword.get(opts, :allowlist, %{tool: @tools})

    with true <- valid_options?(opts),
         true <- valid_roles?(roles),
         true <- valid_profiles?(profiles, allowlist),
         true <- valid_providers?(providers),
         :ok <- Model.validate_registry(models),
         true <- combined_capabilities?(profiles, models),
         true <- valid_routes?(Keyword.get(opts, :routes, %{})),
         :ok <- Catalogue.validate(Keyword.get(opts, :catalogue, %{})) do
      execution = :executor in roles
      capabilities = capabilities(profiles, models)

      environments =
        Enum.flat_map(profiles, &environment/1)
        |> Enum.uniq()

      runtime = [execution: execution, limits: Keyword.get(opts, :limits, [])]

      runtime =
        if execution do
          runtime ++
            [
              handlers: %{
                "agent.native" => {Handler, %{profiles: profiles, model_providers: models}}
              },
              capabilities: capabilities,
              environments: environments,
              providers: providers,
              pools: Keyword.get(opts, :pools, %{})
            ]
        else
          runtime
        end

      if execution,
        do:
          Report.validate_configuration!(
            runtime,
            Limits.new(runtime)
          )

      children =
        if execution,
          do: [{Beamlet.Node.Provider, profiles}, {Beamlet.Node.Runtime, runtime}],
          else: [{Beamlet.Runtime, runtime}]

      children = [
        {Routes,
         routes: Keyword.get(opts, :routes, %{}), catalogue: Keyword.get(opts, :catalogue, %{})}
        | children
      ]

      {:ok,
       if(:authority in roles,
         do: children ++ [{Beamlet.Agent.AuthoritySupervisor, model_providers: models}],
         else: children
       )}
    else
      _ -> {:error, :invalid_node_configuration}
    end
  rescue
    _ -> {:error, :invalid_node_configuration}
  end

  defp capabilities(profiles, models),
    do:
      Enum.uniq(
        Enum.map(profiles, fn {_, p} -> p.capability end) ++
          Enum.map(models, fn {id, _} -> "model.provider:" <> id end)
      )

  defp combined_capabilities?(profiles, models), do: length(capabilities(profiles, models)) <= 32

  defp environment({_, %{environment: environment}}), do: [environment]
  defp environment(_), do: []

  defp valid_options?(opts),
    do:
      Keyword.keyword?(opts) and
        Keyword.keys(opts) --
          [
            :roles,
            :profiles,
            :model_providers,
            :providers,
            :pools,
            :limits,
            :allowlist,
            :routes,
            :catalogue
          ] == []

  defp valid_routes?(routes) when is_map(routes) do
    map_size(routes) <= 64 and
      Enum.all?(routes, fn {id, route} ->
        is_binary(id) and is_map(route) and id == route[:id] and Caller.profile?(route)
      end)
  end

  defp valid_routes?(_), do: false

  defp valid_roles?(roles),
    do:
      is_list(roles) and roles != [] and Enum.uniq(roles) == roles and
        Enum.all?(roles, &(&1 in [:interaction, :authority, :executor]))

  defp valid_providers?(providers),
    do: is_list(providers) and length(providers) < 32 and Enum.all?(providers, &is_pid/1)

  defp valid_profiles?(profiles, %{tool: tools} = allowlist)
       when is_list(tools) do
    is_map(profiles) and map_size(profiles) <= 32 and
      Enum.all?(profiles, &profile?(&1, allowlist))
  end

  defp valid_profiles?(_, _), do: false

  defp allowed_module?(%{type: type, module: module}, allowlist) when type == :tool do
    module in Map.fetch!(allowlist, type) and is_atom(module) and
      Code.ensure_loaded?(module) and native_exports?(type, module)
  end

  defp allowed_module?(_, _), do: false

  defp native_exports?(:tool, module),
    do: function_exported?(module, :descriptor, 0) and function_exported?(module, :invoke, 3)

  defp profile?({id, p}, allowlist) when is_binary(id) and is_map(p) do
    byte_size(id) in 1..128 and String.valid?(id) and
      Map.keys(p) -- [:type, :module, :settings, :capability, :environment] == [] and
      is_binary(p[:capability]) and byte_size(p.capability) in 1..128 and
      is_map(p[:settings]) and
      allowed_module?(p, allowlist)
  end

  defp profile?(_, _), do: false
end
