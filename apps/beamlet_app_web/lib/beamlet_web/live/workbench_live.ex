defmodule Beamlet.Web.WorkbenchLive do
  @moduledoc "实时工作台：公开草稿创建、精确身份打开与单个选中 Agent 的订阅。代际与 pending 锁隔离旧结果和重复操作；显示为替换快照，不构建持久历史，离开只退订。"
  use Beamlet.Web, :live_view
  import Beamlet.Web.ObservationComponents, only: [activities: 1, text: 1, turn: 1]
  alias Beamlet.I18n.Vocabulary
  alias Beamlet.Web.{Agents, Handles, Locale, OwnedCall, Presets, WorkbenchCommands}

  on_mount({Locale, :default})

  @impl true
  @typep socket :: Phoenix.LiveView.Socket.t()
  @typep reply :: {:noreply, socket()}
  @typep assigns :: %{
           required(:draft) => Presets.draft(),
           required(:drafts) => %{
             optional(binary()) => {:ok, Presets.draft()} | {:error, :invalid_draft}
           },
           required(:catalogue) => Presets.description() | nil,
           optional(atom()) => term()
         }
  @spec mount(term(), map(), socket()) :: {:ok, socket()}
  def mount(_, _, socket) do
    {:ok,
     assign(socket,
       handle: nil,
       catalogue: nil,
       draft: %{},
       agents: [],
       descriptors: %{},
       search: "",
       complete: false,
       discovering: false,
       failures: [],
       pending: nil,
       generation: 0,
       ref: nil,
       observer: nil,
       snapshot: nil,
       display: nil,
       status: gettext("Connecting"),
       feedback: "",
       identity: nil,
       input_result: gettext("Not submitted"),
       navigation_result: gettext("Not requested"),
       text: "",
       read_only: false,
       caller: nil,
       confirm: false
     )}
  end

  @impl true
  @spec handle_params(map(), binary(), socket()) :: reply()
  def handle_params(params, uri, socket) do
    socket = Locale.on_params(socket, params, uri)
    leave(socket.assigns.observer)
    if socket.assigns.caller, do: send(socket.assigns.caller, :cancel)
    socket = if params["handle"], do: socket, else: clear_command_feedback(socket)
    generation = socket.assigns.generation + 1

    socket =
      assign(socket,
        handle: params["handle"],
        generation: generation,
        read_only: params["observe"] == "1",
        caller: nil,
        observer: socket.assigns.observer,
        ref: nil,
        display: nil,
        snapshot: nil,
        pending: nil,
        discovering: false
      )

    if connected?(socket) do
      owner = self()

      OwnedCall.start(owner, {:load, generation}, fn ->
        load_catalogue()
      end)

      # This starts an optional owned caller; replies arrive asynchronously.
      _ = open_handle(owner, generation, params["handle"])

      send(self(), :discover)
    end

    {:noreply, socket}
  end

  @impl true
  @spec handle_info(term(), socket()) :: reply()
  def handle_info({:owned, {:load, g}, {catalogue, drafts}}, %{assigns: %{generation: g}} = s)
      when is_map(catalogue) do
    {_, {:ok, draft}} = Enum.at(Enum.sort(drafts), 0, {nil, {:ok, %{}}})

    {:noreply,
     assign(s, catalogue: catalogue, drafts: drafts, draft: draft, status: gettext("Ready"))}
  end

  def handle_info(:discover, %{assigns: %{discovering: true}} = s), do: {:noreply, s}

  def handle_info(:discover, s) do
    OwnedCall.start(self(), {:discover, s.assigns.generation}, fn ->
      WorkbenchCommands.discover()
    end)

    {:noreply, assign(s, discovering: true)}
  end

  def handle_info({:owned, {:discover, g}, {:ok, result}}, %{assigns: %{generation: g}} = s) do
    descriptors =
      Map.new(result.agents, fn d ->
        {Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false), d}
      end)

    agents =
      Enum.map(descriptors, fn {key, d} ->
        %{key: key, id: d.id, authority: Atom.to_string(d.authority)}
      end)

    failures =
      Enum.map(result.failures, fn {n, reason} -> "#{n}: #{Vocabulary.reason(reason)}" end)

    {:noreply,
     assign(s,
       discovering: false,
       descriptors: descriptors,
       agents: agents,
       complete: result.complete,
       failures: failures
     )}
  end

  def handle_info({:owned, {:discover, g}, _}, %{assigns: %{generation: g}} = s),
    do:
      {:noreply,
       assign(s,
         discovering: false,
         complete: false,
         failures: [gettext("Discovery unavailable")]
       )}

  def handle_info({:owned, {:open, g}, {:ok, ref}}, %{assigns: %{generation: g}} = s),
    do: {:noreply, observe(s, ref)}

  def handle_info({:creation, tag, event}, %{assigns: %{pending: tag}} = s) do
    case event do
      {:identity, authority, id} ->
        {:noreply,
         assign(s,
           identity: %{authority: authority, id: id},
           feedback: gettext("Creation dispatched; outcome not yet known")
         )}

      {:confirmed, ref} ->
        {:noreply, observe(assign(s, feedback: gettext("Created instance confirmed")), ref)}

      :input_pending ->
        {:noreply, assign(s, input_result: gettext("Dispatched; acknowledgement unknown"))}

      {:input, result} ->
        {:noreply, assign(s, input_result: outcome(result))}
    end
  end

  def handle_info({:owned, tag, result}, %{assigns: %{pending: tag}} = s) when not is_nil(tag) do
    s = assign(s, pending: nil)

    case result do
      {:navigation, {:ok, handle}} ->
        {:noreply,
         s
         |> assign(
           navigation_result: gettext("Available"),
           feedback: gettext("Created. Initial input: %{input}", input: s.assigns.input_result)
         )
         |> push_patch(to: ~p"/agents/#{handle}")}

      {:child_navigation, {:ok, handle}} ->
        {:noreply, push_patch(s, to: ~p"/agents/#{handle}?observe=1")}

      {:attached, {:ok, handle}} ->
        {:noreply, push_patch(s, to: ~p"/agents/#{handle}")}

      {:attached, {:error, reason}}
      when reason in [
             :stale_agent,
             :not_found,
             :unavailable,
             :timeout,
             :handle_limit,
             :not_authority
           ] ->
        {:noreply,
         assign(s,
           feedback:
             gettext("Exact discovered identity: %{reason}. Refresh discovery explicitly.",
               reason: Vocabulary.reason(reason)
             )
         )}

      {:navigation, _} ->
        {:noreply,
         assign(s,
           navigation_result: gettext("Unavailable"),
           feedback: gettext("Confirmed instance retained here; navigation unavailable")
         )}

      _ ->
        {:noreply, assign(s, feedback: outcome(result))}
    end
  end

  def handle_info({:observation, tag, {:snapshot, snapshot, sink, sequence}}, s) do
    result = handle_info({:observation, tag, {:snapshot, snapshot}}, s)
    send(sink, {:displayed, sequence})
    result
  end

  def handle_info(
        {:observation, {g, ref}, {:snapshot, snapshot}},
        %{assigns: %{generation: g, ref: ref}} = s
      ) do
    {:noreply,
     assign(s,
       snapshot: snapshot,
       display: Map.get(snapshot, :display),
       status: gettext("Observing live context")
     )}
  end

  def handle_info(
        {:observation, {g, ref}, :unavailable},
        %{assigns: %{generation: g, ref: ref}} = s
      ),
      do:
        {:noreply,
         assign(s,
           status: gettext("Observation unavailable; instance outcome unknown"),
           display: nil,
           snapshot: nil
         )}

  def handle_info({:owned, {kind, g}, _}, %{assigns: %{generation: g}} = s)
      when kind in [:load, :open],
      do:
        {:noreply,
         assign(s, feedback: gettext("Configuration or exact identity unavailable / stale"))}

  def handle_info(_, s), do: {:noreply, s}

  @impl true
  @spec handle_event(binary(), map(), socket()) :: reply()
  def handle_event("search", %{"search" => q}, s),
    do: {:noreply, assign(s, search: String.slice(q, 0, 128))}

  def handle_event("discover", _, s) do
    send(self(), :discover)
    {:noreply, s}
  end

  def handle_event("draft", %{"draft" => d}, s) do
    {:noreply, assign(s, draft: update_draft(s.assigns, d))}
  end

  def handle_event("reset", _, s) do
    case get_in(s.assigns, [:drafts, s.assigns.draft["preset"]]) do
      {:ok, d} -> {:noreply, assign(s, draft: d)}
      _ -> {:noreply, s}
    end
  end

  def handle_event("text", %{"text" => text}, s), do: {:noreply, assign(s, text: text)}
  def handle_event("confirm", _, s), do: {:noreply, assign(s, confirm: true)}
  def handle_event("cancel", _, s), do: {:noreply, assign(s, confirm: false)}

  def handle_event(event, _, %{assigns: %{pending: pending}} = s)
      when event in ["create", "input", "stop", "close", "open", "inspect-child"] and
             not is_nil(pending),
      do: {:noreply, s}

  def handle_event(event, _, %{assigns: %{read_only: true}} = s)
      when event in ["input", "stop", "close"],
      do: {:noreply, assign(s, feedback: gettext("Child inspector is observe-only"))}

  def handle_event("inspect-child", %{"key" => key}, s) do
    activity =
      Enum.find((s.assigns.display && s.assigns.display[:activities]) || [], fn a ->
        turn(a[:id]) == key
      end)

    case activity && activity[:child] do
      %Beamlet.Agent.Ref{} = ref ->
        command(clear_command_feedback(s), fn _, _ ->
          {:child_navigation,
           Handles.remember(%{authority: ref.authority, id: ref.id, pid: ref.pid})}
        end)

      _ ->
        {:noreply, assign(s, feedback: gettext("Child identity no longer available"))}
    end
  end

  def handle_event("create", _, %{assigns: %{ref: ref}} = s) when not is_nil(ref),
    do: {:noreply, s}

  def handle_event("create", _, s),
    do:
      command(
        s,
        fn owner, tag -> WorkbenchCommands.create(owner, tag, s.assigns.draft) end,
        16_000
      )

  def handle_event("open", %{"key" => key}, s) do
    case Map.fetch(s.assigns.descriptors, key) do
      {:ok, descriptor} ->
        command(clear_command_feedback(s), fn _, _ -> {:attached, Agents.attach(descriptor)} end)

      _ ->
        {:noreply, assign(s, feedback: gettext("Stale discovery; refresh explicitly"))}
    end
  end

  def handle_event("input", _, s),
    do: command(s, fn _, _ -> Agents.input(s.assigns.ref, s.assigns.text) end)

  def handle_event("stop", _, s),
    do: command(s, fn _, _ -> Beamlet.Agent.stop_turn(s.assigns.ref) end)

  def handle_event("close", _, %{assigns: %{confirm: true}} = s),
    do: command(assign(s, confirm: false), fn _, _ -> Beamlet.Agent.close(s.assigns.ref) end)

  def handle_event(_, _, s), do: {:noreply, s}

  @spec clear_command_feedback(socket()) :: socket()
  defp clear_command_feedback(s) do
    assign(s,
      identity: nil,
      input_result: gettext("Unknown (attached instance)"),
      navigation_result: gettext("Not requested"),
      feedback: "",
      text: "",
      confirm: false
    )
  end

  @spec update_draft(assigns(), Presets.draft()) :: Presets.draft()
  defp update_draft(assigns, d) do
    draft =
      if d["preset"] && d["preset"] != assigns.draft["preset"] do
        case get_in(assigns, [:drafts, d["preset"]]) do
          {:ok, defaults} -> Map.put(defaults, "task", d["task"] || "")
          _ -> %{}
        end
      else
        Map.merge(
          assigns.draft,
          Map.take(
            Map.put_new(d, "tools", []),
            ~w(preset model tools environment authority title task)
          )
        )
      end

    needs_environment =
      Enum.any?(Map.get(draft, "tools", []), fn id ->
        get_in(assigns.catalogue, [:tools, id, :environments]) not in [nil, []]
      end)

    if needs_environment, do: draft, else: Map.put(draft, "environment", nil)
  end

  @spec modified?(assigns()) :: boolean()
  defp modified?(assigns) do
    case get_in(assigns, [:drafts, assigns.draft["preset"]]) do
      {:ok, defaults} -> Map.drop(defaults, ["task"]) != Map.drop(assigns.draft, ["task"])
      _ -> false
    end
  end

  @spec open_handle(pid(), non_neg_integer(), binary() | nil) :: :ok | pid()
  defp open_handle(_, _, nil), do: :ok

  defp open_handle(owner, generation, handle),
    do: OwnedCall.start(owner, {:open, generation}, fn -> Handles.fetch(handle) end)

  @spec load_catalogue() ::
          {Presets.description(),
           %{optional(binary()) => {:ok, Presets.draft()} | {:error, :invalid_draft}}}
  defp load_catalogue do
    catalogue = Presets.describe()
    drafts = Map.new(catalogue.presets, fn {id, _} -> {id, Presets.reset(id)} end)
    {catalogue, drafts}
  end

  @spec command(socket(), (pid(), {non_neg_integer(), reference()} -> term()), non_neg_integer()) ::
          reply()
  defp command(s, fun, timeout \\ 8_000) do
    tag = {s.assigns.generation, make_ref()}
    owner = self()
    caller = OwnedCall.start(owner, tag, fn -> fun.(owner, tag) end, timeout)

    {:noreply,
     assign(s,
       caller: caller,
       pending: tag,
       feedback: gettext("Command pending; no duplicate dispatch")
     )}
  end

  @spec observe(socket(), Beamlet.Agent.Ref.t()) :: socket()
  defp observe(s, ref) do
    leave(s.assigns.observer)
    observer = OwnedCall.observe(self(), {s.assigns.generation, ref}, ref, s.assigns.observer)
    assign(s, ref: ref, observer: observer, display: nil, snapshot: nil)
  end

  @spec leave(pid() | nil) :: :ok | :leave
  defp leave(nil), do: :ok
  defp leave(pid), do: send(pid, :leave)
  @spec outcome(term()) :: binary()
  defp outcome({:accepted, _}), do: gettext("Input accepted")

  defp outcome({:rejected, reason}),
    do: gettext("Rejected: %{reason}", reason: Vocabulary.reason(reason))

  defp outcome(:ok),
    do:
      gettext("Request acknowledged; observe actual state. Stop does not undo external effects.")

  defp outcome({:error, reason}) when is_atom(reason),
    do: gettext("Unavailable / rejected: %{reason}", reason: Vocabulary.reason(reason))

  defp outcome(:configuration_unavailable),
    do: gettext("Configuration unavailable before creation dispatch")

  defp outcome(:invalid_draft),
    do: gettext("Invalid selection or missing configuration; nothing dispatched")

  defp outcome(_),
    do:
      gettext(
        "Outcome unknown / unavailable. No automatic retry. Discover the displayed identity explicitly."
      )

  @spec active?(Beamlet.Agent.snapshot() | nil) :: boolean()
  defp active?(nil), do: true
  defp active?(snapshot), do: snapshot[:status] in [:running, :waiting]
end
