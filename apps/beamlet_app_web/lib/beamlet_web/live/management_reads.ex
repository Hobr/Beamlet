defmodule Beamlet.Web.ManagementReads do
  @moduledoc """
  通过受信配置与公开 Node 投影执行只读管理查询；范围含显式本地 VM 与允许目标。超过 32 的目标显式列为未读，不连接节点或派发业务。

  Read-only management adapters over trusted configuration and public projections.
  """
  alias Beamlet.Node.Cluster

  @typedoc "管理读取的范围与结果，excluded 明示未读目标。"
  @type result :: %{
          connected: [node()],
          targets: [node()],
          distributed: boolean(),
          reads: [{:ok, Beamlet.Node.Observation.aggregate()} | {:error, :invalid_query}],
          excluded: [node()]
        }
  @doc "读取显式本地与允许目标的公开观测。单次最多 32 目标，超出部分列为 excluded；连接、注册就绪和报告新鲜度须分别解释。"
  @spec nodes() :: {:ok, result()} | {:error, :invalid_authority}
  def nodes do
    allowed = Application.get_env(:beamlet_app_web, :host, []) |> Keyword.get(:allowed_nodes, [])

    with {:ok, connected} <- Cluster.connected(allowed),
         {:ok, resolved} <- resolve(allowed) do
      targets = Enum.uniq([node() | resolved])

      # Local is always explicit. If it makes the trusted scope exceed the
      # public 32-target bound, expose the unread target rather than query it.
      {requested, excluded} = Enum.split(targets, 32)
      result = Beamlet.Node.observe(requested)

      {:ok,
       %{
         connected: connected,
         targets: targets,
         distributed: Node.alive?(),
         reads: [result],
         excluded: excluded
       }}
    end
  end

  # Trust is validated once per name; an invalid or unusable allowlist is an
  # explicit configuration failure rather than a crashed or silently partial page.
  @spec resolve([binary()]) :: {:ok, [node()]} | {:error, :invalid_authority}
  defp resolve(allowed) do
    allowed
    |> Enum.reduce_while({:ok, []}, fn name, {:ok, acc} ->
      case Cluster.authority(name, allowed) do
        {:ok, target} -> {:cont, {:ok, [target | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, targets} -> {:ok, Enum.reverse(targets)}
      error -> error
    end
  end
end
