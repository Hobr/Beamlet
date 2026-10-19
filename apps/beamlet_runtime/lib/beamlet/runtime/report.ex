defmodule Beamlet.Runtime.Report do
  @moduledoc false
  # 报告不携带 settings/provider PID；完整信封预算与注册验证共同限制广播内容。
  @keys ~w(node incarnation gateway lease ready execution_ready handlers capabilities environments available utilization)a

  @type pools :: %{optional(binary()) => non_neg_integer()}
  @type registrations :: %{optional(binary()) => {module(), term()}}
  @typedoc """
  选择视图可含公开 handler 标记或本地注册；settings 只留在执行器。

  Selection view accepts either public handler flags or local registrations. Settings remain executor-local.
  """
  @type placement :: %{
          ready: boolean(),
          handlers: %{optional(binary()) => true | {module(), term()}},
          available: pools(),
          capabilities: [binary()],
          environments: [binary()],
          node: node()
        }
  @type t :: %{
          optional(:lease) => integer(),
          node: node(),
          incarnation: reference(),
          gateway: pid() | nil,
          ready: boolean(),
          execution_ready: boolean(),
          handlers: %{optional(binary()) => true},
          capabilities: [binary()],
          environments: [binary()],
          available: pools(),
          utilization: number()
        }
  @spec valid?(term(), pid(), pos_integer()) :: boolean()
  @spec content?(t()) :: boolean()
  @spec identity?(t(), pid()) :: boolean()
  @spec readiness?(t()) :: boolean()
  @spec labels?(term()) :: boolean()
  @spec label?(term()) :: boolean()
  @spec pools?(term(), boolean()) :: boolean()
  @spec handlers?(term()) :: boolean()
  @spec providers?(term()) :: boolean()
  @spec registrations?(term()) :: boolean()
  @spec registration?(term()) :: boolean()
  @spec validate_configuration!(keyword(), Beamlet.Runtime.Limits.t()) :: :ok

  def valid?(r, endpoint, bytes) do
    is_map(r) and Map.keys(r) -- @keys == [] and
      :erlang.external_size({:report, endpoint, make_ref(), r}) <= bytes and
      identity?(r, endpoint) and readiness?(r) and
      content?(r)
  rescue
    _ -> false
  end

  defp content?(r) do
    labels?(r.capabilities) and labels?(r.environments) and
      pools?(r.available, true) and handlers?(r.handlers) and
      is_number(r.utilization) and r.utilization >= 0
  end

  defp identity?(r, endpoint), do: r.node == node(endpoint) and is_reference(r.incarnation)

  defp readiness?(r) do
    is_boolean(r.ready) and r.execution_ready == r.ready and
      (not r.ready or (is_pid(r.gateway) and node(r.gateway) == r.node and is_integer(r.lease)))
  end

  def labels?(items), do: is_list(items) and length(items) <= 32 and Enum.all?(items, &label?/1)
  def label?(x), do: is_binary(x) and byte_size(x) in 1..128 and String.valid?(x)

  def pools?(pools, zero \\ false) do
    is_map(pools) and map_size(pools) <= 32 and
      Enum.all?(pools, fn {k, v} ->
        label?(k) and is_integer(v) and v >= if(zero, do: 0, else: 1) and v <= 3_600_000
      end)
  end

  defp handlers?(handlers) do
    is_map(handlers) and map_size(handlers) <= 32 and
      Enum.all?(handlers, fn {k, v} -> label?(k) and v == true end)
  end

  defp providers?(providers),
    do: is_list(providers) and length(providers) <= 32 and Enum.all?(providers, &is_pid/1)

  defp registrations?(handlers) do
    is_map(handlers) and map_size(handlers) <= 32 and Enum.all?(handlers, &registration?/1)
  end

  defp registration?({kind, {module, settings}}) do
    label?(kind) and is_atom(module) and Code.ensure_loaded?(module) and
      function_exported?(module, :run, 2) and :erlang.external_size(settings) <= 65_536
  end

  defp registration?(_), do: false

  def validate_configuration!(opts, limits) do
    handlers = Keyword.get(opts, :handlers, %{})
    providers = Keyword.get(opts, :providers, [])

    valid =
      registrations?(handlers) and
        pools?(Keyword.get(opts, :pools, %{})) and
        labels?(Keyword.get(opts, :capabilities, [])) and
        labels?(Keyword.get(opts, :environments, [])) and providers?(providers)

    # Reserve full report overhead before advertising; settings/providers never enter a report.
    public = %{
      handlers: Map.new(handlers, fn {k, _} -> {k, true} end),
      available: Keyword.get(opts, :pools, %{}),
      capabilities: Keyword.get(opts, :capabilities, []),
      environments: Keyword.get(opts, :environments, [])
    }

    unless valid and :erlang.external_size(public) + 512 <= limits.report_bytes,
      do: raise(ArgumentError, "invalid executor configuration")

    :ok
  end
end
