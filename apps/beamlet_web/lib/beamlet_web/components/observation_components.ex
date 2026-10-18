defmodule Beamlet.Web.ObservationComponents do
  @moduledoc "Escaped, bounded source projections shared by Web inspectors."
  use Beamlet.Web, :html

  alias Beamlet.I18n.Vocabulary

  attr :display, :map, default: nil
  attr :pending, :boolean, default: false

  attr :diagnostic_handle, :string, default: nil

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

  def text(nil), do: gettext("Unknown / omitted")
  def text(v) when is_binary(v), do: v
  def text(v) when is_atom(v), do: Vocabulary.status(v)
  def text(_), do: gettext("Unsupported content omitted")
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
