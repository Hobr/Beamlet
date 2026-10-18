defmodule Beamlet.Web.ManagementLive do
  use Beamlet.Web, :live_view
  import Beamlet.Web.ObservationComponents
  alias Beamlet.I18n.Vocabulary
  alias Beamlet.Web.{Handles, Locale, ManagementReads, OwnedCall, Presets}

  on_mount({Locale, :default})

  @impl true
  def mount(_, _, socket) do
    {:ok,
     assign(socket,
       generation: 0,
       caller: nil,
       observer: nil,
       pending: false,
       data: nil,
       status: gettext("Unknown / not observed"),
       last: nil,
       handle: nil,
       ref: nil,
       display: nil,
       snapshot: nil,
       activity: nil
     )}
  end

  @impl true
  def handle_params(params, uri, s) do
    s = Locale.on_params(s, params, uri)
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
        status: gettext("Unknown / not observed")
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

    assign(s,
      caller: caller,
      pending: true,
      status: gettext("Reading; previous observation retained")
    )
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
       status: gettext("Exact handle resolved; awaiting live context")
     )}
  end

  def handle_info({:owned, {:management, g}, {:ok, data}}, %{assigns: %{generation: g}} = s) do
    {:noreply,
     assign(s,
       data: data,
       caller: nil,
       pending: false,
       last: DateTime.utc_now() |> DateTime.to_iso8601(),
       status: gettext("Last observation received")
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
       status: gettext("Observing current live context")
     )}
  end

  def handle_info(
        {:observation, {g, ref}, :unavailable},
        %{assigns: %{generation: g, ref: ref}} = s
      ) do
    {:noreply,
     assign(s,
       status:
         gettext("Observation unavailable; last observation retained, current facts unknown")
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
        <nav aria-label={gettext("Management")} class="flex flex-wrap gap-4">
          <.link navigate={~p"/"}>{gettext("Workbench")}</.link>
          <.link navigate={~p"/admin/nodes"}>{gettext("Nodes")}</.link>
          <.link navigate={~p"/admin/presets"}>{gettext("Presets")}</.link>
          <.link navigate={~p"/admin/diagnostics"}>{gettext("Diagnostics")}</.link>
        </nav>
        <Layouts.locale_switcher locale_options={@locale_options} />
      </header>
      <h1 class="text-xl font-bold">
        {gettext("Read-only %{section}", section: section(@live_action))}
      </h1>
      <p>{gettext("Navigation is not authorization. Trusted deployment controls apply.")}</p>
      <p role="status">{@status}</p>
      <p>{gettext("Last observation (Web receipt): %{at}", at: @last || gettext("Unknown"))}</p>
      <button id="refresh" phx-click="refresh" disabled={@pending} class="btn my-4">
        {gettext("Refresh observation")}
      </button>
      <.node_results :if={@live_action == :nodes && @data} data={@data} />
      <.preset_results :if={@live_action == :presets && @data} data={@data} />
      <section :if={@live_action == :diagnostics}>
        <p>
          {gettext(
            "Observe only. Current context, not a complete timeline. Placement unknown unless observed."
          )}
        </p>
        <.link :if={@ref} navigate={~p"/agents/#{@handle}?observe=1"}>
          {gettext("Open observe-only workbench")}
        </.link>
        <p :if={!@ref}>
          {gettext(
            "No exact live handle resolved. Open diagnostics from an existing Agent workspace."
          )}
        </p>
        <p :if={@ref}>
          {gettext("Agent: %{id} · %{authority}",
            id: @ref.id,
            authority: Atom.to_string(@ref.authority)
          )}
        </p>
        <p :if={!@display}>{gettext("Display absent / omitted")}</p>
        <p :if={@display && (@display[:truncated] || @display[:omitted])}>
          {gettext("Source omissions/truncation may apply; context replaces prior display.")}
        </p>
        <p :if={@activity && !selected_activity(@display, @activity)}>
          {gettext("Activity identity stale / unknown; no historical reconstruction.")}
        </p>
        <p :if={@snapshot}>{gettext("Current turn: %{turn}", turn: turn(@snapshot[:turn]))}</p>
        <p :if={@snapshot}>
          {gettext("Business state: %{state}", state: text(@snapshot[:status]))}
        </p>
        <section :if={@display} aria-label={gettext("Retained live context")}>
          <h2 class="font-bold">{gettext("Retained live context")}</h2>
          <p>{gettext("Coverage: %{coverage}", coverage: text(@display[:coverage]))}</p>
          <p :if={@display[:omitted]}>
            {gettext("Omitted entries: %{entries}; activities: %{activities}",
              entries: @display.omitted.entries,
              activities: @display.omitted.activities
            )}
          </p>
          <article :for={entry <- @display[:entries] || []} class="border p-3 my-2">
            <p>{text(entry[:role])} · {turn(entry[:turn])}</p>
            <pre class="whitespace-pre-wrap break-words max-h-64 overflow-auto">{text(
              entry[:content]
            )}</pre>
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
        {gettext(
          "Scope: explicit local VM and configured trusted targets. Distribution: %{distribution}.",
          distribution:
            if(@data.distributed,
              do: Vocabulary.status(:enabled),
              else: gettext("disabled; local path supported")
            )
        )}
      </p>
      <p>
        {gettext(
          "Public read bounds: 32 targets per call, 8 workers, 5 seconds, 1 MiB. Page deadline: 12 seconds. Available is advisory; totals and utilization unknown."
        )}
      </p>
      <p>
        {gettext(
          "Registered readiness is not provider health. Missing or stale reports do not prove death."
        )}
      </p>
      <article :for={target <- @data.targets} class="border rounded-box p-4 my-3 break-words">
        <h2 class="font-bold">{Atom.to_string(target)}</h2>
        <p>
          {gettext("Connection: %{connection}",
            connection:
              cond do
                target == node() -> gettext("local (no distribution required)")
                target in @data.connected -> gettext("connected at read entry")
                true -> Vocabulary.status(:disconnected)
              end
          )}
        </p>
      </article>
      <p :for={target <- @data.excluded}>
        {gettext(
          "Scope partial: %{target} not read (32-target limit including explicit local). Facts unknown.",
          target: Atom.to_string(target)
        )}
      </p>
      <div :for={result <- @data.reads}>
        <div :if={match?({:ok, _}, result)}>
          <p>
            {gettext("Read completeness: %{completeness}",
              completeness:
                if(elem(result, 1).complete,
                  do: Vocabulary.status(:complete),
                  else: gettext("partial / unknown")
                )
            )}
          </p>
          <p :for={{target, reason} <- elem(result, 1).failures}>
            {Atom.to_string(target)}: {text(reason)}
          </p>
          <article :for={{target, facts} <- elem(result, 1).nodes} class="border p-4 my-3">
            <h2>{gettext("%{target} observed facts", target: Atom.to_string(target))}</h2>
            <p>{gettext("Configured: %{configured}", configured: text(facts.configured))}</p>
            <p>{gettext("Configured roles: %{roles}", roles: labels(facts.roles))}</p>
            <p>{gettext("Registered services: %{services}", services: services(facts.services))}</p>
            <.runtime_reports runtime={facts.runtime} />
          </article>
        </div>
        <p :if={!match?({:ok, _}, result)}>{gettext("Read unavailable; facts unknown")}</p>
      </div>
    </section>
    """
  end

  attr :runtime, :any, required: true

  def runtime_reports(assigns) do
    ~H"""
    <div :if={match?({:ok, _}, @runtime)}>
      <p>
        {gettext("Report source: %{source} · coverage: %{coverage}",
          source: text(elem(@runtime, 1).source),
          coverage:
            if(elem(@runtime, 1).complete,
              do: Vocabulary.status(:complete),
              else: Vocabulary.status(:partial)
            )
        )}
      </p>
      <p :if={elem(@runtime, 1).reports == []}>{gettext("No reports; capacity unknown")}</p>
      <div :for={r <- elem(@runtime, 1).reports} class="my-3">
        <p>
          {gettext("%{node} · Report: %{report} · Source receipt age: %{age}",
            node: text(r.node),
            report: text(r.status),
            age: age(r.age_ms)
          )}
        </p>
        <p>
          {gettext("Ready: %{ready} · Execution ready: %{execution_ready}",
            ready: text(r[:ready]),
            execution_ready: text(r[:execution_ready])
          )}
        </p>
        <p>
          {gettext("Capabilities: %{capabilities} · Environments: %{environments}",
            capabilities: labels(r[:capabilities]),
            environments: labels(r[:environments])
          )}
        </p>
        <p :for={{pool, quantity} <- r[:available] || %{}}>
          {gettext("Available %{pool}: %{quantity}", pool: text(pool), quantity: quantity)}
        </p>
        <p :if={!r[:available]}>{gettext("Available capacity unknown")}</p>
      </div>
    </div>
    <p :if={!match?({:ok, _}, @runtime)}>
      {gettext("Runtime reports unavailable / not configured; capacity unknown")}
    </p>
    """
  end

  attr :data, :map, required: true

  def preset_results(assigns) do
    ~H"""
    <section>
      <p>
        {gettext(
          "Configuration source category: trusted startup catalogue. Same public descriptors as creation. No provider probes; online availability unknown."
        )}
      </p>
      <p>
        {gettext("Default authority reference: %{authority}",
          authority: @data.default_authority || gettext("none configured")
        )}
      </p>
      <section :for={kind <- [:presets, :models, :tools, :environments, :authorities]}>
        <h2 class="font-bold mt-4">{section(kind)}</h2>
        <p :if={map_size(@data[kind]) == 0}>
          {gettext("None configured; availability unknown")}
        </p>
        <article :for={{id, entry} <- Enum.sort(@data[kind])} class="border p-3 my-2">
          <h3>{id}: {entry.title}</h3><p>{entry[:description]}</p>
          <p :if={kind == :presets}>
            {gettext(
              "Default model reference: %{model} · Tools: %{tools} · Environment: %{environment}",
              model: text(entry[:model]),
              tools: labels(entry[:tools]),
              environment: environment(entry[:environment])
            )}
          </p>
          <p :if={kind == :tools}>
            {gettext(
              "Compatible environment references: %{environments}. Empty means no environment required.",
              environments: labels(entry[:environments])
            )}
          </p>
        </article>
      </section>
    </section>
    """
  end

  defp section(:nodes), do: gettext("nodes")
  defp section(:presets), do: gettext("presets")
  defp section(:diagnostics), do: gettext("diagnostics")
  defp section(:models), do: gettext("models")
  defp section(:tools), do: gettext("tools")
  defp section(:environments), do: gettext("environments")
  defp section(:authorities), do: gettext("authorities")

  defp labels([]), do: gettext("none")
  defp labels(v) when is_list(v), do: Enum.map_join(v, ", ", &text/1)
  defp labels(_), do: gettext("Unknown")

  defp environment(nil), do: gettext("not required")
  defp environment(id), do: text(id)

  defp failure(:nodes, reason),
    do:
      gettext(
        "Node scope read unavailable: %{reason}. Last observation retained; current facts unknown",
        reason: reason(reason)
      )

  defp failure(:presets, reason),
    do:
      gettext(
        "Catalogue read unavailable: %{reason}. Last observation retained; current facts unknown",
        reason: reason(reason)
      )

  defp failure(_, reason),
    do:
      gettext(
        "Unavailable / stale identity: %{reason}. Last observation retained; current facts unknown",
        reason: reason(reason)
      )

  defp reason({:error, inner}), do: reason(inner)
  defp reason(v) when is_atom(v), do: Vocabulary.reason(v)
  defp reason(_), do: gettext("Unknown")

  defp services(v) when is_map(v),
    do: Enum.map_join(v, ", ", fn {k, value} -> "#{k}: #{text(value)}" end)

  defp services(v), do: text(v)
  defp age(v) when is_integer(v), do: gettext("%{value} ms", value: v)
  defp age(_), do: gettext("Unknown")
end
