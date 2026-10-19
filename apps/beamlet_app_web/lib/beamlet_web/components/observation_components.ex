defmodule Beamlet.Web.ObservationComponents do
  @moduledoc """
  工作台与诊断共用的实时投影组件。以转义文本展示当前活动；源引用散列为不透明关联标签，不据到达顺序猜测轮次，也不重建历史。

  Escaped, bounded source projections shared by Web inspectors.
  """
  use Beamlet.Web, :html

  alias Beamlet.I18n.Vocabulary

  attr :display, :map, default: nil
  attr :pending, :boolean, default: false

  attr :diagnostic_handle, :string, default: nil

  @doc "呈现当前并发活动、缺失/截断与诊断链接；完成活动可能消失，不表示持久事件历史。"
  @spec activities(%{
          optional(:display) => map() | nil,
          optional(:pending) => boolean(),
          optional(:diagnostic_handle) => binary() | nil,
          optional(atom()) => term()
        }) :: Phoenix.LiveView.Rendered.t()
  def activities(assigns) do
    ~H"""
    <section aria-label={gettext("Current concurrent activity")} class="my-4">
      <h2 class="font-bold">{gettext("Current concurrent activity")}</h2>
      <p>
        {gettext(
          "Placement unknown unless observed. Cards are current facts; completed activities may disappear."
        )}
      </p>
      <details
        :for={activity <- (@display && @display[:activities]) || []}
        class="border rounded-box p-3 my-2"
      >
        <summary>
          {text(activity[:kind])} {text(activity[:name])} · {text(activity[:status])} · {turn(
            activity[:turn]
          )}
        </summary>
        <p>{gettext("Activity identity: %{id}", id: turn(activity[:id]))}</p>
        <p>
          {gettext("Operation identity: %{operation} · Attempt identity: %{attempt}",
            operation: turn(activity[:operation]),
            attempt: turn(activity[:attempt])
          )}
        </p>
        <.link
          :if={@diagnostic_handle}
          navigate={
            ~p"/admin/diagnostics?handle=#{@diagnostic_handle}&activity=#{turn(activity[:id])}"
          }
        >{gettext("Inspect activity diagnostics")}</.link>
        <p>{gettext("Placement: %{placement}", placement: text(activity[:placement]))}</p>
        <pre class="whitespace-pre-wrap break-words max-h-64 overflow-auto">{text(
          activity[:arguments]
        )}</pre>
        <pre class="whitespace-pre-wrap break-words max-h-64 overflow-auto">{text(
          activity[:result]
        )}</pre>
        <p :if={activity[:result_omitted] || activity[:truncated]}>
          {gettext("Activity content omitted / truncated")}
        </p>
        <button
          :if={activity[:child]}
          phx-click="inspect-child"
          phx-value-key={turn(activity[:id])}
          class="btn btn-sm"
          disabled={@pending}
        >{gettext("Inspect child (observe only)")}</button>
        <p :if={activity[:child]}>
          {gettext("Child identity observed; observe-only. No command is sent to the child.")}
        </p>
      </details>
    </section>
    """
  end

  @doc "只输出文本、状态词汇或静态省略提示，不 inspect 任意项。"
  @spec text(term()) :: binary()
  def text(nil), do: gettext("Unknown / omitted")
  def text(v) when is_binary(v), do: v
  def text(v) when is_atom(v), do: Vocabulary.status(v)
  def text(_), do: gettext("Unsupported content omitted")
  @doc "将源关联项散列成不透明展示标签；不从标签还原源引用或历史。"
  @spec turn(term()) :: binary()
  def turn(nil), do: gettext("Turn unknown")

  def turn(v),
    do:
      gettext("Turn %{id}",
        id:
          :crypto.hash(:sha256, :erlang.term_to_binary(v))
          |> Base.url_encode64(padding: false)
          |> binary_part(0, 10)
      )
end
