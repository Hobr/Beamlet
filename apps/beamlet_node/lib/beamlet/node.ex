defmodule Beamlet.Node do
  alias Beamlet.Harness.Model
  alias Beamlet.Runtime.Limits
  alias Beamlet.Runtime.Report

  @moduledoc """
  由宿主监督树显式启动的可信角色组合，每 VM 一棵树。支持 interaction/authority/executor 的七种非空组合；没有 Application 回调，不读取宿主配置或自动建库。one_for_all 将角色资源故障耦合，重启不重放业务。

  Trusted role composition, started explicitly by an embedding supervisor.
  """
  use Supervisor
  alias Beamlet.Agent.Integration.{Caller, Handler}
  alias Beamlet.Harness.Catalogue
  alias Beamlet.Node.{Observation, Routes}
  @tools [Beamlet.Harness.Tools.Deterministic, Beamlet.Harness.Tools.WorkspaceRead]

  @doc """
  读取本地安全事实，支持非分布 VM；ready 仅表示注册存在，不证明服务响应或 provider 健康。

  Returns the safe local version1 observation; see `observe/1` for schema/bounds.
  Explicitly supports the local non-distributed VM. No Node tree is represented
  by configured=false, roles=unknown and services=not_configured.
  """
  @typedoc """
  启动时选定的可信角色，非空且不可重复。

  Trusted roles selected once at startup.
  """
  @type role :: :interaction | :authority | :executor
  @typedoc """
  执行器本地工具注册，settings 不进入公开路由或报告。

  Executor-local tool registration; adapter settings and bounded placement labels are open data.
  """
  @type profile :: %{
          optional(:environment) => term(),
          :type => :tool,
          :module => module(),
          :settings => map(),
          :capability => binary()
        }
  @typedoc "以不透明 profile ID 索引的本地工具注册表，最多 32 项。"
  @type profiles :: %{optional(binary()) => profile()}
  @typedoc "显式角色组合配置；model_providers 为可信模块注册，providers 为受监控进程，两者独立。"
  @type options :: [
          {:roles, [role()]}
          | {:profiles, profiles()}
          | {:model_providers, %{optional(binary()) => module()}}
          | {:providers, [pid()]}
          | {:pools, %{optional(binary()) => pos_integer()}}
          | {:limits, keyword()}
          | {:allowlist, %{tool: [module()]}}
          | {:routes, %{optional(binary()) => Beamlet.Agent.Integration.Caller.profile()}}
          | {:catalogue, Beamlet.Harness.Catalogue.t()}
        ]

  @spec observation() :: {:ok, Observation.local_observation()} | {:error, atom()}
  def observation, do: Observation.local()

  @doc """
  最多聚合 32 个可信 atom 节点，8 并发共享 5 秒预算；逐节点保留失败，complete 只覆盖请求集合。

  Observes at most32 distinct trusted atom targets, including local node().
  Returns `{:ok, %{nodes: %{target => observation}, failures: %{target => reason},
  complete: boolean}}`; malformed/duplicate/excess targets return invalid_query.
  Each version1 observation has node, configured, roles (startup declarations or
  unknown), services and runtime (`{:ok, Runtime observation}` or static error).
  Services map authority/executor/runtime/routes to ready/unavailable/not_configured;
  ready means required local registrations exist, not a responsiveness/health probe.
  Interaction is a declaration, not an additional service. Missing configured
  metadata fails unavailable rather than inventing roles. Runtime read errors
  preserve the node with complete=false; all failures are explicit.

  Max8 concurrent requests share one5s receive deadline including queued targets.
  Complete serialized reply <=1MiB with16KiB reserved for failures. Oversize node
  observations fail limit. Static errors: invalid_query/unavailable/timeout/limit.
  Only initially connected remote targets are eligible; no atoms are created or
  connections requested. OTP can reconnect after that precheck. Caller exit or
  timeout abandons replies; remote reads may start late and finish within their
  own finite relative budget. Nested reads share that source deadline. Scheduler
  delays are possible; this is not hard real time or remote cancellation.
  Reads are non-atomic, advisory and dispatch no model/tool work or retries.
  """
  @spec observe(term()) :: {:ok, Observation.aggregate()} | {:error, :invalid_query}
  def observe(nodes), do: Observation.observe(nodes)

  @spec profile(binary()) :: {:ok, Beamlet.Agent.Integration.Caller.profile()} | :error
  @doc "查找公开工具路由；返回 {:ok, route} 或 :error，不包含本地 settings。"
  def profile(id), do: GenServer.call(Routes, {:profile, id})
  @spec catalogue() :: {:ok, Beamlet.Harness.Catalogue.t()}
  @doc "读取启动时的公开纯数据工具目录。"
  def catalogue, do: GenServer.call(Routes, :catalogue)
  @spec start_link(options()) :: Supervisor.on_start()
  @doc "显式启动本 VM 唯一角色监督树，非法配置使启动失败。"
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  @spec init(options()) :: {:ok, {Supervisor.sup_flags(), [Supervisor.child_spec()]}}
  def init(opts) do
    case configuration(opts) do
      {:ok, children} -> Supervisor.init(children, strategy: :one_for_all)
      {:error, reason} -> raise ArgumentError, Atom.to_string(reason)
    end
  end

  @spec configuration(term()) ::
          {:ok, [Supervisor.child_spec() | {module(), term()}]}
          | {:error, :invalid_node_configuration}
  @doc "预检可信配置并返回子树描述或 invalid_node_configuration，不启动子进程；所有角色组合均校验 Runtime limits。"
  def configuration(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: configure(opts), else: {:error, :invalid_node_configuration}
  end

  def configuration(_), do: {:error, :invalid_node_configuration}

  @spec configure(keyword()) ::
          {:ok, [{module(), term()}]} | {:error, :invalid_node_configuration}
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

      limits = Limits.new(runtime)

      if execution,
        do:
          Report.validate_configuration!(
            runtime,
            limits
          )

      children =
        if execution,
          do: [{Beamlet.Node.Provider, profiles}, {Beamlet.Node.Runtime, runtime}],
          else: [{Beamlet.Runtime, runtime}]

      children = [
        {Routes,
         roles: roles,
         routes: Keyword.get(opts, :routes, %{}),
         catalogue: Keyword.get(opts, :catalogue, %{})}
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

  @spec capabilities(profiles(), %{optional(binary()) => module()}) :: [binary()]
  defp capabilities(profiles, models),
    do:
      Enum.uniq(
        Enum.map(profiles, fn {_, p} -> p.capability end) ++
          Enum.map(models, fn {id, _} -> "model.provider:" <> id end)
      )

  @spec combined_capabilities?(profiles(), %{optional(binary()) => module()}) :: boolean()
  defp combined_capabilities?(profiles, models), do: length(capabilities(profiles, models)) <= 32

  @spec environment(term()) :: [term()]
  defp environment({_, %{environment: environment}}), do: [environment]
  defp environment(_), do: []

  @spec valid_options?(keyword()) :: boolean()
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

  @spec valid_routes?(term()) :: boolean()
  defp valid_routes?(routes) when is_map(routes) do
    map_size(routes) <= 64 and
      Enum.all?(routes, fn {id, route} ->
        is_binary(id) and is_map(route) and id == route[:id] and Caller.profile?(route)
      end)
  end

  defp valid_routes?(_), do: false

  @spec valid_roles?(term()) :: boolean()
  defp valid_roles?(roles),
    do:
      is_list(roles) and roles != [] and Enum.uniq(roles) == roles and
        Enum.all?(roles, &(&1 in [:interaction, :authority, :executor]))

  @spec valid_providers?(term()) :: boolean()
  defp valid_providers?(providers),
    do: is_list(providers) and length(providers) < 32 and Enum.all?(providers, &is_pid/1)

  @spec valid_profiles?(term(), term()) :: boolean()
  defp valid_profiles?(profiles, %{tool: tools} = allowlist)
       when is_list(tools) do
    is_map(profiles) and map_size(profiles) <= 32 and
      Enum.all?(profiles, &profile?(&1, allowlist))
  end

  defp valid_profiles?(_, _), do: false

  @spec allowed_module?(term(), %{tool: [module()]}) :: boolean()
  defp allowed_module?(%{type: type, module: module}, allowlist) when type == :tool do
    module in Map.fetch!(allowlist, type) and is_atom(module) and
      Code.ensure_loaded?(module) and native_exports?(type, module)
  end

  defp allowed_module?(_, _), do: false

  @spec native_exports?(:tool, module()) :: boolean()
  defp native_exports?(:tool, module),
    do: function_exported?(module, :descriptor, 0) and function_exported?(module, :invoke, 3)

  @spec profile?(term(), %{tool: [module()]}) :: boolean()
  defp profile?({id, p}, allowlist) when is_binary(id) and is_map(p) do
    byte_size(id) in 1..128 and String.valid?(id) and
      Map.keys(p) -- [:type, :module, :settings, :capability, :environment] == [] and
      is_binary(p[:capability]) and byte_size(p.capability) in 1..128 and
      is_map(p[:settings]) and
      allowed_module?(p, allowlist)
  end

  defp profile?(_, _), do: false
end
