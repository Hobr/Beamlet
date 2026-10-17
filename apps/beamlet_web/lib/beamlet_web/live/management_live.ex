defmodule Beamlet.Web.ManagementLive do
  use Beamlet.Web, :live_view
  import Beamlet.Web.ObservationComponents
  alias Beamlet.Web.{Handles, ManagementReads, OwnedCall, Presets}

  @impl true
  def mount(_, _, socket) do
    {:ok,
     assign(socket,
       generation: 0,
       caller: nil,
       observer: nil,
       pending: false,
       data: nil,
       status: "Unknown / not observed",
       last: nil,
       handle: nil,
       ref: nil,
       display: nil,
       snapshot: nil,
       activity: nil
     )}
  end

  @impl true
  def handle_params(params, _, s) do
    if s.assigns.caller, do: send(s.assigns.caller, :cancel)
    if s.assigns.observer, do: send(s.assigns.observer, :leave)

    s =
      assign(s,
        generation: s.assigns.generation + 1,
        caller: nil,
        pending: false,
        data: nil,
        last: nil,
        ref: nil,
        display: nil,
        snapshot: nil,
        handle: params["handle"],
        activity: params["activity"],
        status: "Unknown / not observed"
      )

    {:noreply, if(connected?(s), do: read(s), else: s)}
  end

  defp read(%{assigns: %{pending: true}} = s), do: s

  defp read(s) do
    action = s.assigns.live_action
    handle = s.assigns.handle

    caller =
      OwnedCall.start(
        self(),
        {:management, s.assigns.generation},
        fn ->
          case action do
            :nodes -> ManagementReads.nodes()
            :presets -> {:ok, Presets.describe()}
            :diagnostics -> Handles.fetch(handle)
          end
        end,
        12_000
      )

    assign(s, caller: caller, pending: true, status: "Reading; previous observation retained")
  end

  @impl true
  def handle_event("refresh", _, s), do: {:noreply, read(s)}
  # Forged business/admin events have no command path, including input/stop/close.
  def handle_event(_, _, s), do: {:noreply, s}

  @impl true
  def handle_info(
        {:owned, {:management, g}, {:ok, ref}},
        %{assigns: %{generation: g, live_action: :diagnostics}} = s
      ) do
    observer = OwnedCall.observe(self(), {g, ref}, ref, s.assigns.observer)

    {:noreply,
     assign(s,
       ref: ref,
       observer: observer,
       caller: nil,
       pending: false,
       status: "Exact handle resolved; awaiting live context"
     )}
  end

  def handle_info({:owned, {:management, g}, {:ok, data}}, %{assigns: %{generation: g}} = s) do
    {:noreply,
     assign(s,
       data: data,
       caller: nil,
       pending: false,
       last: DateTime.utc_now() |> DateTime.to_iso8601(),
       status: "Last observation received"
     )}
  end

  def handle_info({:owned, {:management, g}, result}, %{assigns: %{generation: g}} = s) do
    {:noreply,
     assign(s,
       caller: nil,
       pending: false,
       status: failure(s.assigns.live_action, result)
     )}
  end

  def handle_info(
        {:observation, {g, ref}, {:snapshot, snapshot, sink, sequence}},
        %{assigns: %{generation: g, ref: ref}} = s
      ) do
    send(sink, {:displayed, sequence})

    {:noreply,
     assign(s,
       snapshot: snapshot,
       display: Map.get(snapshot, :display),
       last: DateTime.utc_now() |> DateTime.to_iso8601(),
       status: "Observing current live context"
     )}
  end

  def handle_info(
        {:observation, {g, ref}, :unavailable},
        %{assigns: %{generation: g, ref: ref}} = s
      ) do
    {:noreply,
     assign(s,
       status: "Observation unavailable; last observation retained, current facts unknown"
     )}
  end

  def handle_info(_, s), do: {:noreply, s}

  defp selected_activity(nil, _), do: nil

  defp selected_activity(display, key),
    do: Enum.find(display[:activities] || [], &(turn(&1[:id]) == key))

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-base-200 text-base-content p-4 lg:p-8">
      <Layouts.flash_group flash={@flash} />
      <header class="flex flex-wrap gap-4 items-center mb-6">
        <.link navigate={~p"/"} class="text-2xl font-bold">Beamlet</.link>
        <nav aria-label="Management" class="flex flex-wrap gap-4">
          <.link navigate={~p"/"}>Workbench</.link>
          <.link navigate={~p"/admin/nodes"}>Nodes</.link>
          <.link navigate={~p"/admin/presets"}>Presets</.link>
          <.link navigate={~p"/admin/diagnostics"}>Diagnostics</.link>
        </nav>
      </header>
      <h1 class="text-xl font-bold">Read-only {text(@live_action)}</h1>
      <p>Navigation is not authorization. Trusted deployment controls apply.</p>
      <p role="status">{@status}</p>
      <p>Last observation (Web receipt): {@last || "Unknown"}</p>
      <button id="refresh" phx-click="refresh" disabled={@pending} class="btn my-4">Refresh observation</button>
      <.node_results :if={@live_action == :nodes && @data} data={@data} />
      <.preset_results :if={@live_action == :presets && @data} data={@data} />
      <section :if={@live_action == :diagnostics}>
        <p>
          Observe only. Current context, not a complete timeline. Placement unknown unless observed.
        </p>
        <.link :if={@ref} navigate={~p"/agents/#{@handle}?observe=1"}>Open observe-only workbench</.link>
        <p :if={!@ref}>
          No exact live handle resolved. Open diagnostics from an existing Agent workspace.
        </p>
        <p :if={@ref}>Agent: {@ref.id} · {Atom.to_string(@ref.authority)}</p>
        <p :if={!@display}>Display absent / omitted</p>
        <p :if={@display && (@display[:truncated] || @display[:omitted])}>
          Source omissions/truncation may apply; context replaces prior display.
        </p>
        <p :if={@activity && !selected_activity(@display, @activity)}>
          Activity identity stale / unknown; no historical reconstruction.
        </p>
        <p :if={@snapshot}>Current turn: {turn(@snapshot[:turn])}</p>
        <p :if={@snapshot}>Business state: {text(@snapshot[:status])}</p>
        <section :if={@display} aria-label="Retained live context">
          <h2 class="font-bold">Retained live context</h2>
          <p>Coverage: {text(@display[:coverage])}</p>
          <p :if={@display[:omitted]}>
            Omitted entries: {@display.omitted.entries}; activities: {@display.omitted.activities}
          </p>
          <article :for={entry <- @display[:entries] || []} class="border p-3 my-2">
            <p>{text(entry[:role])} · {turn(entry[:turn])}</p>
            <pre class="whitespace-pre-wrap break-words max-h-64 overflow-auto">{text(entry[:content])}</pre>
          </article>
        </section>
        <.activities display={@display} pending={true} />
      </section>
    </main>
    """
  end

  attr :data, :map, required: true

  def node_results(assigns) do
    ~H"""
    <section>
      <p>
        Scope: explicit local VM and configured trusted targets. Distribution: {if @data.distributed,
          do: "enabled",
          else: "disabled; local path supported"}.
      </p>
      <p>
        Public read bounds: 32 targets per call, 8 workers, 5 seconds, 1 MiB. Page deadline: 12 seconds. Available is advisory; totals and utilization unknown.
      </p>
      <p>Registered readiness is not provider health. Missing or stale reports do not prove death.</p>
      <article :for={target <- @data.targets} class="border rounded-box p-4 my-3 break-words">
        <h2 class="font-bold">{Atom.to_string(target)}</h2>
        <p>
          Connection: {cond do
            target == node() -> "local (no distribution required)"
            target in @data.connected -> "connected at read entry"
            true -> "disconnected"
          end}
        </p>
      </article>
      <p :for={target <- @data.excluded}>
        Scope partial: {Atom.to_string(target)} not read (32-target limit including explicit local). Facts unknown.
      </p>
      <div :for={result <- @data.reads}>
        <div :if={match?({:ok, _}, result)}>
          <p>
            Read completeness: {if elem(result, 1).complete, do: "complete", else: "partial / unknown"}
          </p>
          <p :for={{target, reason} <- elem(result, 1).failures}>
            {Atom.to_string(target)}: {text(reason)}
          </p>
          <article :for={{target, facts} <- elem(result, 1).nodes} class="border p-4 my-3">
            <h2>{Atom.to_string(target)} observed facts</h2>
            <p>Configured: {text(facts.configured)}</p>
            <p>Configured roles: {labels(facts.roles)}</p>
            <p>Registered services: {services(facts.services)}</p>
            <.runtime_reports runtime={facts.runtime} />
          </article>
        </div>
        <p :if={!match?({:ok, _}, result)}>Read unavailable; facts unknown</p>
      </div>
    </section>
    """
  end

  attr :runtime, :any, required: true

  def runtime_reports(assigns) do
    ~H"""
    <div :if={match?({:ok, _}, @runtime)}>
      <p>
        Report source: {text(elem(@runtime, 1).source)} · coverage: {if elem(@runtime, 1).complete,
          do: "complete",
          else: "partial"}
      </p>
      <p :if={elem(@runtime, 1).reports == []}>No reports; capacity unknown</p>
      <div :for={r <- elem(@runtime, 1).reports} class="my-3">
        <p>{text(r.node)} · Report: {text(r.status)} · Source receipt age: {age(r.age_ms)}</p>
        <p>Ready: {text(r[:ready])} · Execution ready: {text(r[:execution_ready])}</p>
        <p>Capabilities: {labels(r[:capabilities])} · Environments: {labels(r[:environments])}</p>
        <p :for={{pool, quantity} <- r[:available] || %{}}>Available {text(pool)}: {quantity}</p>
        <p :if={!r[:available]}>Available capacity unknown</p>
      </div>
    </div>
    <p :if={!match?({:ok, _}, @runtime)}>
      Runtime reports unavailable / not configured; capacity unknown
    </p>
    """
  end

  attr :data, :map, required: true

  def preset_results(assigns) do
    ~H"""
    <section>
      <p>
        Configuration source category: trusted startup catalogue. Same public descriptors as creation. No provider probes; online availability unknown.
      </p>
      <p>Default authority reference: {@data.default_authority || "none configured"}</p>
      <section :for={kind <- [:presets, :models, :tools, :environments, :authorities]}>
        <h2 class="font-bold mt-4">{text(kind)}</h2>
        <p :if={map_size(@data[kind]) == 0}>None configured; availability unknown</p>
        <article :for={{id, entry} <- Enum.sort(@data[kind])} class="border p-3 my-2">
          <h3>{id}: {entry.title}</h3><p>{entry[:description]}</p>
          <p :if={kind == :presets}>
            Default model reference: {text(entry[:model])} · Tools: {labels(entry[:tools])} · Environment: {environment(
              entry[:environment]
            )}
          </p>
          <p :if={kind == :tools}>
            Compatible environment references: {labels(entry[:environments])}. Empty means no environment required.
          </p>
        </article>
      </section>
    </section>
    """
  end

  defp labels([]), do: "none"
  defp labels(v) when is_list(v), do: Enum.map_join(v, ", ", &text/1)
  defp labels(_), do: "Unknown"

  defp environment(nil), do: "not required"
  defp environment(id), do: text(id)

  defp failure(:nodes, reason),
    do:
      "Node scope read unavailable: #{reason(reason)}. Last observation retained; current facts unknown"

  defp failure(:presets, reason),
    do:
      "Catalogue read unavailable: #{reason(reason)}. Last observation retained; current facts unknown"

  defp failure(_, reason),
    do:
      "Unavailable / stale identity: #{reason(reason)}. Last observation retained; current facts unknown"

  defp reason(:deadline), do: "deadline"
  defp reason(:unavailable), do: "unavailable"
  defp reason({:error, inner}), do: reason(inner)
  defp reason(v) when is_atom(v), do: Atom.to_string(v)
  defp reason(_), do: "unknown"

  defp services(v) when is_map(v),
    do: Enum.map_join(v, ", ", fn {k, value} -> "#{k}: #{text(value)}" end)

  defp services(v), do: text(v)
  defp age(v) when is_integer(v), do: "#{v} ms"
  defp age(_), do: "Unknown"
end
