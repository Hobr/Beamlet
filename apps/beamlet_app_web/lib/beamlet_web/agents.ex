defmodule Beamlet.Web.Agents do
  @moduledoc """
  创建与输入的一次性适配器。分别返回创建确认、临时导航及输入结果；确认丢失时保留不确定性，不重试或关闭实例。阻塞调用须由上层拥有并设置 UI 截止时间。

  One-attempt creation and input; ambiguous acknowledgements never trigger retries.
  """
  alias Beamlet.{Agent, Node}
  alias Beamlet.Web.{Handles, Presets}

  @typedoc "区分已接受、已知拒绝与确认未知；未知不触发重试。"
  @type input_result ::
          {:accepted, Agent.turn()}
          | {:rejected, :busy | :invalid_or_oversize_input | :stale_ref | :invalid_command}
          | :input_unknown
  @typedoc "创建确认、导航和初始输入分别报告；已确认 Ref 不随导航失败丢弃。"
  @type creation_result ::
          {:created,
           %{ref: Agent.Ref.t(), navigation: Handles.navigation(), input: input_result()}}
          | {:create_unknown, %{authority: node(), id: binary()}}
          | {:rejected, :invalid_draft}
  @doc "读取显式受信目标的实时身份；保留 complete/failures，发现不是原子集群快照。"
  @spec discover(term()) :: {:ok, Node.Agents.result()} | {:error, :invalid_query}
  def discover(targets), do: Node.Agents.discover(targets)
  @doc "精确核对发现描述符并生成临时导航句柄，不提交输入。"
  @spec attach(term()) :: Handles.navigation()
  def attach(descriptor), do: Handles.remember(descriptor)

  @doc "尝试创建一次实例；创建确认与输入/导航结果须分别处理，不因反馈丢失自动重发。"
  @spec create(term()) :: creation_result()
  def create(draft) do
    case Presets.resolve(draft) do
      {:ok, resolved} ->
        authority =
          if resolved.authority == :local,
            do: node(),
            else: String.to_existing_atom(resolved.authority)

        id = "web-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

        case Agent.start(authority, Keyword.put(resolved.options, :id, id)) do
          {:ok, ref} ->
            navigation = Handles.remember(%{authority: ref.authority, id: ref.id, pid: ref.pid})
            {:created, %{ref: ref, navigation: navigation, input: input(ref, resolved.task)}}

          _ ->
            {:create_unknown, %{authority: authority, id: id}}
        end

      _ ->
        {:rejected, :invalid_draft}
    end
  end

  @doc "向精确 Ref 提交一轮文本，保留后端的忙碌、无效输入及不可用结果；不自动排队或重试。"
  @spec input(Agent.Ref.t(), term()) :: input_result()
  def input(ref, text) do
    case Agent.input(ref, text) do
      {:ok, turn} ->
        {:accepted, turn}

      {:error, reason}
      when reason in [:busy, :invalid_or_oversize_input, :stale_ref, :invalid_command] ->
        {:rejected, reason}

      _ ->
        :input_unknown
    end
  end
end
