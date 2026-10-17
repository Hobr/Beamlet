defmodule Beamlet.Web.ObservationComponents do
  @moduledoc "Escaped, bounded source projections shared by Web inspectors."
  use Beamlet.Web, :html

  attr :display, :map, default: nil
  attr :pending, :boolean, default: false

  attr :diagnostic_handle, :string, default: nil

  def activities(assigns) do
    ~H"""
    <section aria-label="Current concurrent activity" class="my-4">
      <h2 class="font-bold">Current concurrent activity</h2>
      <p>
        Placement unknown unless observed. Cards are current facts; completed activities may disappear.
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
        <p>Activity identity: {turn(activity[:id])}</p>
        <p>
          Operation identity: {turn(activity[:operation])} · Attempt identity: {turn(
            activity[:attempt]
          )}
        </p>
        <.link
          :if={@diagnostic_handle}
          navigate={
            ~p"/admin/diagnostics?handle=#{@diagnostic_handle}&activity=#{turn(activity[:id])}"
          }
        >Inspect activity diagnostics</.link>
        <p>Placement: {text(activity[:placement])}</p>
        <pre class="whitespace-pre-wrap break-words max-h-64 overflow-auto">{text(activity[:arguments])}</pre>
        <pre class="whitespace-pre-wrap break-words max-h-64 overflow-auto">{text(activity[:result])}</pre>
        <p :if={activity[:result_omitted] || activity[:truncated]}>
          Activity content omitted / truncated
        </p>
        <button
          :if={activity[:child]}
          phx-click="inspect-child"
          phx-value-key={turn(activity[:id])}
          class="btn btn-sm"
          disabled={@pending}
        >Inspect child (observe only)</button>
        <p :if={activity[:child]}>
          Child identity observed; observe-only. No command is sent to the child.
        </p>
      </details>
    </section>
    """
  end

  def text(nil), do: "Unknown / omitted"
  def text(v) when is_binary(v), do: v
  def text(v) when is_atom(v), do: Atom.to_string(v)
  def text(_), do: "Unsupported content omitted"
  def turn(nil), do: "Turn unknown"

  def turn(v),
    do:
      "Turn " <>
        (:crypto.hash(:sha256, :erlang.term_to_binary(v))
         |> Base.url_encode64(padding: false)
         |> binary_part(0, 10))
end
