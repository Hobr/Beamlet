defmodule Beamlet.Agent.Server do
  alias Beamlet.Agent.{Display, Durable, ModelBinding}
  @moduledoc false
  use GenServer, restart: :temporary
  alias Beamlet.Actions.{Operation, Result}
  alias Beamlet.Agent.{Delegation, Integration.Caller, OperationOwner, Ref}
  alias Beamlet.Harness.{Catalogue, Context}
  alias Beamlet.Harness.Model
  alias Beamlet.Runtime.Directory

  def start_link(opts) do
    if valid_options?(opts) do
      with {:ok, limit} <- deployment_limit() do
        GenServer.start_link(__MODULE__, {opts, limit},
          name: {:via, Registry, {Beamlet.Agent.Registry, Keyword.fetch!(opts, :id)}}
        )
      end
    else
      {:error, :invalid_agent_options}
    end
  end

  defp deployment_limit do
    if Process.whereis(Directory),
      do: {:ok, Directory.limits().operation_bytes},
      else: {:ok, 262_144}
  catch
    :exit, _ -> {:error, :runtime_unavailable}
  end

  @impl true
  def init({opts, limit}) do
    catalogue = Keyword.get(opts, :catalogue, %{})

    if valid_options?(opts) do
      if opts[:delegator], do: Process.link(opts[:delegator])

      ref = %Ref{
        authority: node(),
        id: Keyword.fetch!(opts, :id),
        incarnation: make_ref(),
        pid: self()
      }

      {:ok,
       %{
         ref: ref,
         catalogue: catalogue,
         model: Keyword.fetch!(opts, :model),
         tools: Keyword.get(opts, :tools, %{}),
         messages: [],
         display_entries: [],
         display_metadata: Keyword.get(opts, :display_metadata, %{}),
         turn: nil,
         terminal_turn: nil,
         status: :idle,
         steps: 0,
         pending: %{},
         owners: %{},
         authority_resources: Process.whereis(Beamlet.Agent.Resources),
         operation_limit: limit,
         order: [],
         results: %{},
         subscribers: %{},
         sequence: 0,
         assistant: nil,
         children: %{},
         helpers: %{},
         continuation: false,
         delegator: if(opts[:delegator], do: Process.monitor(opts[:delegator]), else: nil),
         peers: %{},
         inbox: %{},
         progress: nil,
         final: nil,
         durable: Keyword.get(opts, :durable),
         durable_batch: %{},
         restored_pending: [],
         durable_continuation: "await_input"
       }
       |> restore_state(Keyword.get(opts, :restored))}
    else
      {:stop, :invalid_agent_options}
    end
  end

  defp valid_options?(opts, binding_validator \\ &ModelBinding.valid?/1)

  defp valid_options?(opts, binding_validator) when is_list(opts) do
    if Keyword.keyword?(opts) and Catalogue.validate(Keyword.get(opts, :catalogue, %{})) == :ok and
         Display.metadata?(Keyword.get(opts, :display_metadata, %{})),
       do: valid_keyword_options?(opts, binding_validator),
       else: false
  end

  defp valid_options?(_, _), do: false

  defp valid_keyword_options?(opts, binding_validator) do
    tools = Keyword.get(opts, :tools, %{})

    valid_option_keys?(opts) and
      valid_id?(opts[:id]) and
      valid_delegator?(opts[:delegator]) and
      valid_durable_pair?(opts[:durable], opts[:restored]) and
      binding_validator.(opts[:model]) and
      valid_tools?(tools)
  end

  defp valid_option_keys?(opts) do
    Keyword.keys(opts) --
      [:id, :model, :tools, :catalogue, :delegator, :display_metadata, :durable, :restored] == []
  end

  defp valid_delegator?(delegator), do: is_nil(delegator) or is_pid(delegator)

  defp valid_durable_pair?(durable, restored) do
    (is_nil(durable) or match?(%Durable{}, durable)) and
      (is_nil(restored) or is_map(restored)) and
      durable_pair?(durable, restored)
  end

  defp valid_tools?(tools) do
    is_map(tools) and map_size(tools) <= 64 and
      Enum.all?(tools, fn {name, profile} -> is_binary(name) and Caller.profile?(profile) end)
  end

  defp valid_id?(id), do: is_binary(id) and byte_size(id) in 1..128 and String.valid?(id)

  defp delegation_specs?(specs) do
    is_list(specs) and length(specs) in 1..8 and Enum.all?(specs, &delegation_spec?/1)
  end

  defp delegation_spec?(spec) when is_map(spec) do
    Map.keys(spec) -- [:authority, :options, :input] == [] and
      is_atom(spec[:authority]) and is_list(spec[:options]) and Keyword.keyword?(spec[:options]) and
      valid_options?(spec.options, &ModelBinding.portable?/1) and is_binary(spec[:input]) and
      byte_size(spec.input) <= 65_536
  end

  defp delegation_spec?(_), do: false

  defp start_children(specs, group, authority) do
    parent = self()

    Enum.reduce_while(Enum.with_index(specs), {:ok, %{}}, fn item, {:ok, children} ->
      start_delegation(parent, group, item, children, authority)
    end)
  end

  defp start_delegation(parent, group, {spec, id}, children, authority) do
    {pid, monitor} =
      spawn_monitor(fn -> Delegation.launch(parent, group, id, spec, authority) end)

    {:cont, {:ok, Map.put(children, id, %{pid: pid, monitor: monitor})}}
  end

  @impl true
  def handle_call(:ref, _, s), do: {:reply, {:ok, s.ref}, s}
  def handle_call({inc, cmd}, _, %{ref: %{incarnation: inc}} = s), do: control(cmd, s)
  def handle_call(_, _, s), do: {:reply, {:error, :stale_ref}, s}

  defp control({:delegate, specs, opts}, s) do
    valid =
      delegation_specs?(specs) and Keyword.keyword?(opts) and
        Keyword.keys(opts) -- [:continue] == [] and
        is_boolean(Keyword.get(opts, :continue, false))

    if s.status in [:idle, :done, :error, :stopped] and map_size(s.helpers) == 0 and valid do
      group = make_ref()

      case start_children(specs, group, s.authority_resources) do
        {:ok, children} ->
          accept_delegation(s, group, children, opts)

        {:error, reason, children} ->
          helpers = helper_monitors(children)
          {:reply, {:error, reason}, %{s | helpers: helpers}}
      end
    else
      {:reply, {:error, :invalid_or_busy_delegation}, s}
    end
  end

  defp control({:peer_take, id}, s) do
    {entry, inbox} = Map.pop(s.inbox, id)
    {:reply, {:ok, entry}, %{s | inbox: inbox}}
  end

  defp control(:inbox, s), do: {:reply, {:ok, s.inbox}, s}

  defp control({:peer_request, %Ref{} = target, payload, ttl}, s) do
    id = make_ref()
    envelope = {:peer_request, target, s.ref, s.turn, id, payload, ttl}

    retained =
      {id,
       %{
         sender: s.ref,
         sender_turn: s.turn,
         receiver_turn: make_ref(),
         payload: payload,
         ttl: ttl
       }}

    if bounded_message?(payload) and envelope?(envelope) and envelope?(retained) and
         is_integer(ttl) and ttl in 1..60_000 and
         map_size(s.peers) + map_size(s.inbox) < 16 do
      monitor = Process.monitor(target.pid)
      send(target.pid, {:peer_request, target, s.ref, s.turn, id, payload, ttl})
      Process.send_after(self(), {:peer_expire, id}, ttl)
      peers = Map.put(s.peers, id, %{target: target, turn: s.turn, monitor: monitor})
      {:reply, {:ok, id}, %{s | peers: peers}}
    else
      {:reply, {:error, :peer_limit_or_invalid_message}, s}
    end
  end

  defp control({:peer_reply, id, payload}, s) do
    case Map.fetch(s.inbox, id) do
      {:ok, %{sender: sender, sender_turn: turn, receiver_turn: receiver_turn}}
      when receiver_turn == s.turn ->
        envelope = {:peer_response, sender, s.ref, turn, id, {:ok, payload}}

        if bounded_message?(payload) and envelope?(envelope) and
             envelope?({id, %{result: {:ok, payload}}}) do
          send(sender.pid, {:peer_response, sender, s.ref, turn, id, {:ok, payload}})
          {:reply, :ok, %{s | inbox: Map.delete(s.inbox, id)}}
        else
          {:reply, {:error, :message_limit}, s}
        end

      _ ->
        {:reply, {:error, :stale_peer_request}, s}
    end
  end

  defp control(:close, s), do: {:stop, :normal, :ok, stop_owned(s)}
  defp control(:snapshot, s), do: {:reply, {:ok, view(s)}, s}
  defp control({:snapshot, []}, s), do: control(:snapshot, s)
  defp control({:snapshot, [view: :display]}, s), do: {:reply, {:ok, view(s, :display)}, s}

  defp control({:input, text}, s), do: control({:input, text, nil}, s)

  defp control({:input, text, command_id}, %{status: status} = s)
       when status in [:idle, :done, :error, :stopped] do
    with true <- Enum.all?(s.owners, fn {_, o} -> Map.get(o, :completed, false) end),
         true <- is_binary(text) and String.valid?(text) and byte_size(text) <= 65_536,
         {:ok, messages} <- Context.append(s.messages, [%{"role" => "user", "content" => text}]),
         :ok <- Model.validate_request(%{messages: messages, catalogue: s.catalogue}),
         {:ok, _} <-
           Caller.operation(
             s.model,
             %{"messages" => messages, "catalogue" => s.catalogue},
             s.operation_limit
           ) do
      if s.durable do
        durable_input(s, messages, command_id)
      else
        s = %{
          s
          | turn: make_ref(),
            terminal_turn: nil,
            status: :running,
            steps: 0,
            final: nil,
            progress: nil
        }

        s = Display.annotate(s, messages)
        send(self(), {:advance, s.turn})
        {:reply, {:ok, s.turn}, publish(s)}
      end
    else
      _ -> {:reply, {:error, :invalid_or_oversize_input}, s}
    end
  end

  defp control({:input, _, _}, s), do: {:reply, {:error, :busy}, s}

  defp control(:stop, s) do
    {s, blocked, block_error} = block_turn(s, :unconfirmed_stop)
    pending = s.pending
    Enum.each(s.owners, fn {_, o} -> send(o.pid, :stop) end)
    Enum.each(s.children, fn {_, child} -> send(child.pid, :stop) end)
    Enum.each(s.peers, fn {_, peer} -> Process.demonitor(peer.monitor, [:flush]) end)

    s =
      publish(%{
        s
        | status: stop_status(blocked, block_error),
          terminal_turn: s.turn || s.terminal_turn,
          pending: %{},
          turn: nil,
          children: %{},
          assistant: nil,
          results: %{},
          order: [],
          peers: %{},
          inbox: %{}
      })

    Enum.each(pending, fn {_, p} ->
      Process.demonitor(p.monitor, [:flush])
      send(p.owner, :stop)
    end)

    {:reply, :ok, s}
  end

  defp control({:subscribe, pid}, s), do: control({:subscribe, pid, []}, s)

  defp control({:subscribe, pid, opts}, s) when is_pid(pid) and opts in [[], [view: :display]] do
    projection = if opts == [], do: :default, else: :display

    cond do
      Map.has_key?(s.subscribers, pid) ->
        {:reply, {:error, :already_subscribed}, s}

      map_size(s.subscribers) >= 32 ->
        {:reply, {:error, :subscriber_limit}, s}

      true ->
        seq = s.sequence + 1
        send(pid, {:beamlet_agent, s.ref, seq, {:snapshot, view(s, projection)}})

        sub = %{
          monitor: Process.monitor(pid),
          outstanding: MapSet.new([seq]),
          dirty: false,
          view: projection
        }

        {:reply, :ok, %{s | sequence: seq, subscribers: Map.put(s.subscribers, pid, sub)}}
    end
  end

  defp control({:unsubscribe, pid}, s) do
    {sub, subscribers} = Map.pop(s.subscribers, pid)
    if sub, do: Process.demonitor(sub.monitor, [:flush])
    {:reply, :ok, %{s | subscribers: subscribers}}
  end

  defp control({:ack, pid, seq}, s) do
    case Map.fetch(s.subscribers, pid) do
      {:ok, sub} ->
        sub = %{sub | outstanding: MapSet.delete(sub.outstanding, seq)}
        s = %{s | subscribers: Map.put(s.subscribers, pid, sub)}
        {:reply, :ok, if(sub.dirty, do: publish(s), else: s)}

      :error ->
        {:reply, {:error, :not_subscribed}, s}
    end
  end

  @resume_positions ~w(await_input completed blocked await_model_result reply_recorded)

  defp control({:continue, version, decisions, command_id}, %{status: :paused} = s) do
    continue(s, version, decisions, command_id)
  end

  defp control({:continue, _, _, _}, s), do: {:reply, {:error, :not_paused}, s}

  defp control(_, s), do: {:reply, {:error, :invalid_command}, s}

  @impl true
  def handle_info(
        {:delegation_result, group, _id, _child, _turn, {:error, :delegation_capacity}},
        %{turn: group, status: :waiting} = s
      ) do
    {:noreply, fail(s, :delegation_capacity)}
  end

  def handle_info(
        {:delegation_result, group, id, child, turn, result},
        %{turn: group, status: :waiting} = s
      ) do
    case Map.pop(s.children, id) do
      {nil, _} ->
        {:noreply, s}

      {entry, rest} ->
        _ = entry
        results = Map.put(s.results, id, %{child: child, turn: turn, result: result})
        s = %{s | children: rest, results: results}

        {:noreply, if(map_size(rest) == 0, do: joined(s), else: publish_activity(s))}
    end
  end

  def handle_info({:peer_request, target, sender, turn, id, payload, ttl}, s) do
    envelope = {:peer_request, target, sender, turn, id, payload, ttl}

    entry = %{
      sender: sender,
      sender_turn: turn,
      receiver_turn: s.turn,
      payload: payload,
      ttl: ttl
    }

    if target == s.ref and bounded_message?(payload) and envelope?(envelope) and
         envelope?({id, entry}) and
         map_size(s.peers) + map_size(s.inbox) < 16 and
         is_integer(ttl) and ttl in 1..60_000 do
      Process.send_after(self(), {:inbox_expire, id}, ttl)
      {:noreply, %{s | inbox: Map.put(s.inbox, id, entry)}}
    else
      send(sender.pid, {:peer_response, sender, s.ref, turn, id, {:error, :peer_rejected}})
      {:noreply, s}
    end
  end

  def handle_info({:peer_response, target, sender, turn, id, result}, s) do
    valid =
      envelope?({:peer_response, target, sender, turn, id, result}) and
        envelope?({id, %{result: result}})

    case if(valid, do: Map.pop(s.peers, id), else: {nil, s.peers}) do
      {%{target: ^sender, turn: ^turn, monitor: monitor}, rest}
      when target == s.ref and turn == s.turn ->
        Process.demonitor(monitor, [:flush])

        inbox =
          if map_size(s.inbox) < 16, do: Map.put(s.inbox, id, %{result: result}), else: s.inbox

        {:noreply, %{s | peers: rest, inbox: inbox}}

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:peer_expire, id}, s) do
    {entry, peers} = Map.pop(s.peers, id)
    if entry, do: Process.demonitor(entry.monitor, [:flush])
    inbox = if entry, do: Map.put(s.inbox, id, %{result: {:error, :peer_expired}}), else: s.inbox
    Process.send_after(self(), {:inbox_expire, id}, 60_000)
    {:noreply, %{s | peers: peers, inbox: inbox}}
  end

  def handle_info({:inbox_expire, id}, s), do: {:noreply, %{s | inbox: Map.delete(s.inbox, id)}}

  def handle_info({:advance, turn}, %{turn: turn, status: :running} = s) do
    cond do
      map_size(s.owners) > 0 ->
        Process.send_after(self(), {:advance, turn}, 1)
        {:noreply, s}

      s.steps >= 16 ->
        {:noreply, fail(s, :step_limit)}

      true ->
        request = %{"messages" => s.messages, "catalogue" => s.catalogue}
        {:noreply, dispatch(%{s | steps: s.steps + 1}, s.model, request, :model)}
    end
  end

  def handle_info({:beamlet_operation, ref, {:progress, attempt, seq, value}}, s) do
    case Map.fetch(s.pending, ref.id) do
      {:ok, pending}
      when pending.ref == ref and pending.turn == s.turn ->
        if progress_valid?(pending, attempt, seq, value, ref) do
          send(pending.owner, {:ack, seq})

          {:noreply,
           publish(%{
             s
             | pending: Map.put(s.pending, ref.id, %{pending | attempt: attempt, sequence: seq}),
               progress: %{
                 operation_id: ref.id,
                 tool: pending.key,
                 attempt: attempt,
                 value: value
               }
           })}
        else
          {:noreply, s}
        end

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:beamlet_operation, ref, {:result, %Result{} = result}}, s) do
    case Map.pop(s.pending, ref.id) do
      {%{ref: ^ref} = pending, rest}
      when result.operation_id == ref.id and pending.turn == s.turn ->
        if Result.valid?(result) and
             (is_nil(pending.attempt) or result.metadata[:attempt_id] == pending.attempt) do
          send(pending.owner, :finished)

          owners = completed_owner(s.owners, pending.owner)

          Process.demonitor(pending.monitor, [:flush])
          {:noreply, complete(%{s | pending: rest, owners: owners}, pending.key, result)}
        else
          {:noreply, s}
        end

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:batch_retired, turn, assistant}, %{turn: turn, status: :running} = s) do
    {:noreply, batch(s, assistant)}
  end

  def handle_info({:resource_retired, pid}, s) do
    lost =
      Enum.any?(s.owners, fn {_, o} ->
        o.pid == pid and o.turn == s.turn and s.status == :running and
          not Map.get(o, :completed, false)
      end)

    s = if lost, do: fail(s, :infrastructure_lost), else: s

    {:noreply,
     %{
       s
       | owners: Map.reject(s.owners, fn {_, o} -> o.pid == pid end),
         helpers: Map.reject(s.helpers, fn {_, helper} -> helper == pid end)
     }}
  end

  def handle_info({:DOWN, mon, :process, pid, _}, s) do
    active_owner_lost =
      Enum.any?(s.owners, fn {_, owner} ->
        owner.monitor == mon and owner.turn == s.turn and s.status == :running and
          not Map.get(owner, :completed, false)
      end)

    cond do
      s.delegator == mon ->
        {:stop, :normal, stop_owned(s)}

      active_owner_lost ->
        {:noreply, fail(s, :infrastructure_lost)}

      Enum.any?(s.pending, fn {_, p} -> p.monitor == mon end) ->
        {:noreply, fail(s, :infrastructure_lost)}

      Enum.any?(s.children, fn {_, c} -> c.monitor == mon end) ->
        {id, _} = Enum.find(s.children, fn {_, c} -> c.monitor == mon end)
        send(self(), {:delegation_result, s.turn, id, nil, nil, {:error, :child_lost}})
        {:noreply, s}

      true ->
        {lost, kept} = Enum.split_with(s.peers, fn {_, p} -> p.monitor == mon end)

        inbox =
          Enum.reduce(lost, s.inbox, fn {id, _}, inbox ->
            Process.send_after(self(), {:inbox_expire, id}, 60_000)
            Map.put(inbox, id, %{result: {:error, :peer_lost}})
          end)

        {:noreply,
         %{s | subscribers: Map.delete(s.subscribers, pid), peers: Map.new(kept), inbox: inbox}}
    end
  end

  def handle_info(
        {:child_observed, group, id, %Ref{} = child, turn},
        %{turn: group, status: :waiting} = s
      ) do
    case Map.fetch(s.children, id) do
      {:ok, entry} ->
        children = Map.put(s.children, id, Map.merge(entry, %{ref: child, turn: turn}))
        {:noreply, publish_activity(%{s | children: children})}

      :error ->
        {:noreply, s}
    end
  end

  def handle_info({:child_startup, helper, group, ticket}, s) do
    if s.turn == group and s.status == :waiting and
         Enum.any?(s.children, fn {_, c} -> c.pid == helper end) do
      send(helper, {:startup_authorized, ticket})
    else
      send(helper, :stop)
    end

    {:noreply, s}
  end

  def handle_info({:operation_ready, token, ref}, s) do
    case s.owners[token] do
      %{turn: turn} = owner when turn == s.turn and s.status == :running ->
        pending = %{
          ref: ref,
          key: owner.key,
          turn: turn,
          owner: owner.pid,
          monitor: Process.monitor(ref.pid),
          attempt: nil,
          sequence: 0
        }

        {:noreply, publish_activity(%{s | pending: Map.put(s.pending, ref.id, pending)})}

      owner ->
        if owner, do: send(owner.pid, :stop)
        {:noreply, s}
    end
  end

  def handle_info({:operation_failed, token, _}, s) do
    case s.owners[token] do
      %{turn: turn} when turn == s.turn and s.status == :running ->
        {:noreply, fail(s, :dispatch_failed)}

      _ ->
        {:noreply, s}
    end
  end

  def handle_info(_, s), do: {:noreply, s}

  defp completed_owner(owners, pid) do
    Map.new(owners, fn {token, owner} ->
      {token, if(owner.pid == pid, do: Map.put(owner, :completed, true), else: owner)}
    end)
  end

  defp progress_valid?(pending, attempt, seq, value, ref) do
    is_binary(attempt) and byte_size(attempt) in 1..128 and
      is_integer(seq) and seq > pending.sequence and
      (is_nil(pending.attempt) or pending.attempt == attempt) and
      Beamlet.Actions.bounded?(value, 8192) and
      :erlang.external_size({:beamlet_operation, ref, {:progress, attempt, seq, value}}) <= 8192
  end

  defp helper_monitors(children), do: Map.new(children, fn {_, c} -> {c.monitor, c.pid} end)

  defp accept_delegation(s, group, children, opts) do
    s = %{
      s
      | turn: group,
        terminal_turn: nil,
        status: :waiting,
        children: children,
        helpers: Map.new(children, fn {_, c} -> {c.monitor, c.pid} end),
        results: %{},
        continuation: Keyword.get(opts, :continue, false),
        progress: nil,
        final: nil
    }

    {:reply, {:ok, group}, publish(s)}
  end

  defp joined(s) do
    results = s.results |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&child_observation/1)

    if s.continuation do
      case append_child_observations(s.messages, results) do
        {:ok, messages} ->
          send(self(), {:advance, s.turn})
          publish(%{Display.annotate(s, messages) | status: :running, steps: 0, results: %{}})

        _ ->
          fail(s, :context_limit)
      end
    else
      publish(%{s | status: :done, final: results, results: %{}})
    end
  end

  defp append_child_observations(messages, results) do
    with {:ok, content} <- Jason.encode(results) do
      Context.append(messages, [%{"role" => "user", "content" => content}])
    end
  rescue
    _ -> {:error, :invalid_child_observation}
  end

  defp child_observation({_, r}) do
    {status, value} = r.result
    %{status: status, value: value}
  end

  defp dispatch(s, profile, request, key) do
    case Caller.operation(profile, request, s.operation_limit) do
      {:ok, operation} ->
        start_operation(s, operation, key, step_dispatch(s))

      error ->
        fail(s, %{type: :dispatch_failed, reason: error})
    end
  end

  # The model step of a durable turn is durable too: an executor configured for
  # durable work rejects an ephemeral admission instead of running it.
  defp step_dispatch(%{durable: %Durable{} = durable}) do
    case Durable.model_persistence(durable) do
      {:ok, persistence} -> {:persistence, persistence}
      {:error, _reason} -> :ephemeral
    end
  end

  defp step_dispatch(_s), do: :ephemeral

  defp start_operation(s, operation, key, dispatch) do
    with true <- map_size(s.owners) < 8,
         {:ok, opts} <- dispatch_options(s, dispatch) do
      token = make_ref()
      agent = self()

      {pid, monitor} =
        spawn_monitor(fn ->
          OperationOwner.run(agent, token, operation, s.authority_resources, opts)
        end)

      owner = %{pid: pid, monitor: monitor, key: key, turn: s.turn}
      publish_activity(%{s | owners: Map.put(s.owners, token, owner)})
    else
      {:error, reason} -> fail(s, reason)
      _ -> fail(s, %{type: :dispatch_failed, reason: :capacity})
    end
  end

  defp dispatch_options(_s, :ephemeral), do: {:ok, []}
  defp dispatch_options(_s, {:persistence, persistence}), do: {:ok, [persistence: persistence]}

  # A durable Tool Operation is dispatched onto the attempt its batch already
  # committed: the Runtime must not mint an unrelated id the batch cannot consume.
  defp dispatch_options(s, prepared) do
    case Durable.persistence(s.durable, prepared) do
      {:ok, persistence} -> {:ok, [persistence: persistence, prepared: prepared]}
      {:error, reason} -> {:error, reason}
    end
  end

  defp canonical_reply(reply, catalogue) do
    case Model.validate_reply(reply, catalogue) do
      :ok -> {:ok, Map.put(reply, :assistant, Model.assistant_message(reply))}
      _ -> {:error, :invalid_reply}
    end
  end

  defp complete(%{durable: %Durable{}} = s, :model, %{status: :uncertain}),
    do: fail(s, :uncertain_external_effect)

  defp complete(s, :model, %{status: :ok, value: reply}) do
    case record_reply(s, reply) do
      {:ok, s} -> complete_reply(s, reply)
      {:error, reason} -> fail(s, reason)
    end
  end

  defp complete(s, :model, result),
    do:
      fail(s, %{
        type: :model_failed,
        status: result.status,
        reason: result.reason,
        operation_id: result.operation_id
      })

  # An uncertain external effect is never an ordinary tool observation: a durable
  # turn stops here and waits for an explicit decision.
  defp complete(%{durable: %Durable{}} = s, _id, %{status: :uncertain}),
    do: fail(s, :uncertain_external_effect)

  defp complete(s, id, result) do
    case Jason.encode(%{status: result.status, value: result.value, reason: result.reason}) do
      {:ok, content} -> complete_tool(s, id, content)
      _ -> fail(s, :invalid_tool_observation)
    end
  rescue
    _ -> fail(s, :invalid_tool_observation)
  end

  defp complete_reply(s, reply) do
    case canonical_reply(reply, s.catalogue) do
      {:ok, %{kind: :text, assistant: assistant, content: content}} ->
        case Context.append(s.messages, [assistant]) do
          {:ok, messages} ->
            publish(%{Display.annotate(s, messages) | status: :done, final: content})

          _ ->
            fail(s, :context_limit)
        end

      {:ok, %{kind: :tool_calls, assistant: assistant}} ->
        batch(s, assistant)

      _ ->
        fail(s, :invalid_reply)
    end
  end

  defp complete_tool(s, id, content) do
    observation = %{
      "role" => "tool",
      "call_id" => id,
      "content" => content
    }

    s = %{s | results: Map.put(s.results, id, observation)}

    if map_size(s.pending) == 0 and map_size(s.results) == length(s.order) do
      additions = [s.assistant | Enum.map(s.order, &Map.fetch!(s.results, &1))]

      case Context.append(s.messages, additions) do
        {:ok, messages} ->
          apply_consumption(s, messages)

        _ ->
          fail(s, :context_limit)
      end
    else
      publish_activity(s)
    end
  end

  defp apply_consumption(s, messages) do
    case commit_consumption(s, messages) do
      {:ok, s} ->
        send(self(), {:advance, s.turn})

        publish_activity(%{
          Display.annotate(s, messages)
          | results: %{},
            order: [],
            assistant: nil
        })

      {:error, reason} ->
        fail(s, reason)
    end
  end

  defp batch(s, assistant) when map_size(s.owners) > 0 do
    Process.send_after(self(), {:batch_retired, s.turn, assistant}, 1)
    s
  end

  defp batch(s, assistant) do
    with {:ok, calls} <- Catalogue.batch(assistant["calls"], s.catalogue),
         true <- Enum.all?(calls, &Map.has_key?(s.tools, &1.name)),
         true <- length(s.messages) + 1 + length(calls) <= 128,
         {:ok, messages} <- Context.append(s.messages, [assistant]),
         {:ok, operations} <- tool_operations(s, calls),
         :ok <- durable_dispatch(s),
         {:ok, s} <- commit_batch(s, assistant, calls, operations, messages) do
      Enum.reduce_while(calls, s, &dispatch_tool/2)
    else
      {:error, :missing_durable_runtime} -> fail(s, :missing_durable_runtime)
      _ -> fail(s, :invalid_tool_batch)
    end
  end

  defp tool_operations(s, calls) do
    Enum.reduce_while(calls, {:ok, []}, fn call, {:ok, acc} ->
      case Caller.operation(s.tools[call.name], call.arguments, s.operation_limit) do
        {:ok, operation} -> {:cont, {:ok, [%{id: call.id, operation: operation} | acc]}}
        _ -> {:halt, :invalid_tool_batch}
      end
    end)
    |> case do
      {:ok, operations} -> {:ok, Enum.reverse(operations)}
      :invalid_tool_batch -> {:error, :invalid_tool_batch}
    end
  end

  # A durable batch is only dispatchable through a configured Runtime; falling
  # back to ephemeral dispatch would leave the committed rows unaccepted.
  defp durable_dispatch(%{durable: nil}), do: :ok

  defp durable_dispatch(%{durable: %Durable{} = durable}) do
    case Durable.runtime(durable) do
      {:ok, _runtime} -> :ok
      {:error, _reason} -> {:error, :missing_durable_runtime}
    end
  end

  defp dispatch_tool(call, acc) do
    next =
      case Map.get(acc.durable_batch, call.id) do
        %{operation: operation, prepared: prepared} ->
          start_operation(acc, operation, call.id, prepared)

        nil ->
          dispatch(acc, acc.tools[call.name], call.arguments, call.id)
      end

    if next.status == :error, do: {:halt, next}, else: {:cont, next}
  end

  defp envelope?(value), do: :erlang.external_size(value) <= 8192

  defp bounded_message?(payload) do
    :erlang.external_size(payload) <= 8192 and
      match?(
        {:ok, _},
        Operation.new(kind: "peer.message", payload: %{"data" => payload})
      )
  end

  defp stop_owned(s) do
    Enum.each(s.children, fn {_, c} -> send(c.pid, :stop) end)
    Enum.each(s.owners, fn {_, o} -> send(o.pid, :stop) end)
    s
  end

  # An explicit stop records the durable fact only while a turn is in flight.
  defp block_turn(%{durable: %Durable{} = durable, turn: turn} = s, reason)
       when not is_nil(turn) do
    case Durable.block(durable, reason) do
      {:ok, blocked} ->
        {%{s | durable: %{durable | version: blocked.version}, durable_continuation: "blocked"},
         true, nil}

      {:error, error} ->
        {s, false, error}
    end
  end

  defp block_turn(s, _reason), do: {s, false, nil}

  # A stop that could not record its durable fact must not read as a recorded stop.
  defp stop_status(true, _error), do: :paused
  defp stop_status(false, nil), do: :stopped
  defp stop_status(false, _error), do: :error

  defp fail(%{durable: nil} = s, reason), do: do_fail(%{s | status: :error}, reason)

  # A durable failure is a durable fact: the blocked checkpoint commits first and
  # its version is kept, so the instance pauses for an explicit decision instead
  # of disappearing with an unreachable continuation.
  defp fail(%{durable: %Durable{} = durable} = s, reason) do
    case Durable.block(durable, durable_reason(reason)) do
      {:ok, blocked} ->
        do_fail(
          %{
            s
            | status: :paused,
              durable: %{durable | version: blocked.version},
              durable_continuation: "blocked"
          },
          reason
        )

      {:error, error} ->
        do_fail(%{s | status: :error}, {:block_write_failed, error})
    end
  end

  defp do_fail(s, reason) do
    stop_owned(s)

    Enum.each(s.pending, fn {_, p} ->
      Process.demonitor(p.monitor, [:flush])
      send(p.owner, :stop)
    end)

    publish(%{
      s
      | terminal_turn: s.turn || s.terminal_turn,
        final: reason,
        pending: %{},
        turn: nil,
        children: %{},
        assistant: nil,
        results: %{},
        order: [],
        durable_batch: %{}
    })
  end

  ## Durable seams (opt-in only)

  defp durable_pair?(nil, nil), do: true
  defp durable_pair?(nil, _restored), do: false
  defp durable_pair?(%Durable{}, _restored), do: true
  defp durable_pair?(_, _), do: false

  defp restore_state(state, nil), do: state

  defp restore_state(state, %{checkpoint: data, durable: durable}) do
    messages = Map.get(data, "messages", [])

    %{
      state
      | messages: [],
        status: :paused,
        turn: Map.get(data, "turn_id"),
        steps: restored_step(Map.get(data, "step")),
        assistant: restored_assistant(Map.get(data, "assistant")),
        order: Map.get(data, "order", []),
        restored_pending: Map.get(data, "pending", []),
        durable: durable,
        durable_continuation: Map.get(data, "continuation", "await_input"),
        results: %{}
    }
    # The projection is rebuilt from restored messages; annotations stay in memory.
    |> Display.annotate(messages)
  end

  defp restored_step(step) when is_integer(step), do: step |> max(0) |> min(16)
  defp restored_step(_), do: 0

  defp durable_input(s, messages, command_id) do
    attrs = %{
      command_id: command_id || Ecto.UUID.generate(),
      turn_id: Ecto.UUID.generate(),
      messages: messages,
      checkpoint_id: Ecto.UUID.generate()
    }

    case Durable.accept_input(s.durable, attrs) do
      {:ok, accepted} ->
        durable = %{
          s.durable
          | turn_id: accepted.turn_id,
            version: accepted.version,
            generation: accepted.generation
        }

        s = %{
          s
          | durable: durable,
            turn: accepted.turn_id,
            terminal_turn: nil,
            steps: 0,
            final: nil,
            progress: nil,
            durable_continuation: "await_model_result",
            status: if(accepted.replayed?, do: s.status, else: :running)
        }

        if accepted.replayed? do
          {:reply, {:ok, s.turn}, s}
        else
          s = Display.annotate(s, messages)
          send(self(), {:advance, s.turn})
          {:reply, {:ok, s.turn}, publish(s)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, s}
    end
  end

  defp record_reply(%{durable: nil} = s, _reply), do: {:ok, s}

  defp record_reply(%{durable: %Durable{} = durable} = s, reply) do
    case plain_reply(reply) do
      {:ok, reply} -> persist_reply(s, durable, reply)
      :error -> {:error, :invalid_reply}
    end
  end

  defp persist_reply(s, durable, reply) do
    attrs = %{
      request: %{"messages" => s.messages, "catalogue" => s.catalogue},
      messages: s.messages,
      reply: reply,
      checkpoint_id: Ecto.UUID.generate(),
      step: s.steps
    }

    case Durable.record_reply(durable, attrs) do
      {:ok, response} ->
        {:ok,
         %{
           s
           | durable: %{durable | version: response.version, step: s.steps},
             durable_continuation: "reply_recorded"
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp commit_batch(%{durable: nil} = s, assistant, calls, _operations, _messages) do
    {:ok, %{s | assistant: assistant, order: Enum.map(calls, & &1.id), results: %{}}}
  end

  defp commit_batch(%{durable: %Durable{} = durable} = s, assistant, calls, operations, messages) do
    attrs = %{
      calls: operations,
      messages: messages,
      assistant: assistant,
      step: s.steps,
      checkpoint_id: Ecto.UUID.generate()
    }

    case Durable.prepare_batch(durable, attrs) do
      {:ok, response} ->
        batch =
          operations
          |> Enum.zip_with(response.operations, fn call, prepared ->
            {call.id, %{operation: call.operation, prepared: prepared}}
          end)
          |> Map.new()

        {:ok,
         %{
           s
           | assistant: assistant,
             order: Enum.map(calls, & &1.id),
             results: %{},
             durable_batch: batch,
             durable: %{durable | version: response.version, step: s.steps},
             durable_continuation: "await_tool_results"
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp commit_consumption(%{durable: nil} = s, _messages), do: {:ok, s}

  defp commit_consumption(%{durable: %Durable{} = durable} = s, messages) do
    operations =
      Enum.map(s.order, fn call_id ->
        %{operation_id: Map.fetch!(s.durable_batch, call_id).prepared["operation_id"]}
      end)

    attrs = %{
      operations: operations,
      messages: messages,
      order: s.order,
      step: s.steps,
      checkpoint_id: Ecto.UUID.generate()
    }

    case Durable.consume_results(durable, attrs) do
      {:ok, response} ->
        {:ok,
         %{
           s
           | durable: %{durable | version: response.version},
             durable_batch: %{},
             durable_continuation: "await_model_result"
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp continue(s, version, decisions, command_id) do
    durable = s.durable

    cond do
      is_nil(durable) ->
        {:reply, {:error, :not_durable}, s}

      version != durable.version ->
        {:reply, {:error, :stale_version}, s}

      # A position the Server cannot resume is refused before the decision commits.
      s.durable_continuation not in @resume_positions ->
        {:reply, {:error, {:unsupported_continuation, s.durable_continuation}}, s}

      true ->
        attrs = %{
          command_id: command_id || Ecto.UUID.generate(),
          checkpoint_id: Ecto.UUID.generate(),
          decision: decisions
        }

        case Durable.decide(durable, attrs) do
          {:ok, decision} -> resume(s, decision)
          {:error, reason} -> {:reply, {:error, reason}, s}
        end
    end
  end

  defp resume(s, decision) do
    durable = %{s.durable | version: decision.version, generation: decision.generation}
    s = %{s | durable: durable, durable_continuation: decision.continuation}

    case decision.continuation do
      "await_input" ->
        s = %{s | status: :idle, turn: nil, restored_pending: [], order: [], results: %{}}
        {:reply, {:ok, view(s)}, publish(s)}

      "await_model_result" ->
        s = %{s | status: :running, turn: durable.turn_id, terminal_turn: nil}
        send(self(), {:advance, s.turn})
        {:reply, {:ok, view(s)}, publish(s)}

      "reply_recorded" ->
        s = replay_reply(%{s | status: :running, turn: durable.turn_id})
        {:reply, {:ok, view(s)}, s}

      position ->
        {:reply, {:error, {:unsupported_continuation, position}}, s}
    end
  end

  # The stored reply is re-validated, never re-requested from the model.
  defp replay_reply(s) do
    case s.assistant do
      nil ->
        fail(s, :invalid_reply)

      assistant ->
        reply = %{
          kind: reply_kind(assistant["kind"]),
          content: assistant["content"],
          calls: Enum.map(assistant["calls"] || [], &restored_call/1)
        }

        complete_reply(s, reply)
    end
  end

  defp reply_kind("text"), do: :text
  defp reply_kind("tool_calls"), do: :tool_calls
  defp reply_kind(_), do: nil

  defp restored_call(%{"id" => id, "name" => name, "arguments" => arguments}),
    do: %{id: id, name: name, arguments: arguments}

  defp restored_call(_), do: %{id: nil, name: nil, arguments: nil}

  defp restored_assistant(%{"kind" => _} = assistant), do: assistant
  defp restored_assistant(_), do: nil

  # The reply is persisted before validation, so it must be normalized to plain
  # data without raising on whatever a provider returned.
  defp plain_reply(reply) when is_map(reply) do
    kind = Map.get(reply, :kind)
    content = Map.get(reply, :content)
    calls = Map.get(reply, :calls, [])

    if kind in [:text, :tool_calls] and is_list(calls) and Enum.all?(calls, &plain_call?/1) do
      {:ok,
       %{
         "kind" => Atom.to_string(kind),
         "content" => content,
         "calls" => Enum.map(calls, &plain_call/1)
       }}
    else
      :error
    end
  end

  defp plain_reply(_), do: :error

  defp plain_call?(%{id: id, name: name, arguments: arguments} = call) do
    map_size(call) == 3 and is_binary(id) and is_binary(name) and is_map(arguments)
  end

  defp plain_call?(_), do: false

  defp plain_call(%{id: id, name: name, arguments: arguments}),
    do: %{"id" => id, "name" => name, "arguments" => arguments}

  defp durable_reason(reason) when is_atom(reason), do: reason
  defp durable_reason(%{type: type}), do: type
  defp durable_reason(_), do: :uncertain

  defp view(s), do: Map.take(s, [:ref, :turn, :terminal_turn, :status, :steps, :final, :progress])

  defp view(s, :default), do: view(s)
  defp view(s, :display), do: Display.project(view(s), s)

  defp publish_activity(s), do: publish(s, [:display])

  defp publish(s, views \\ [:default, :display]) do
    s =
      if :erlang.external_size(view(s)) > 1_048_000,
        do: %{s | status: :error, final: :snapshot_limit},
        else: s

    seq = s.sequence + 1

    subscribers =
      Map.new(s.subscribers, fn {pid, sub} ->
        cond do
          sub.view not in views ->
            {pid, sub}

          MapSet.size(sub.outstanding) < 16 ->
            send(pid, {:beamlet_agent, s.ref, seq, {:snapshot, view(s, sub.view)}})
            {pid, %{sub | outstanding: MapSet.put(sub.outstanding, seq), dirty: false}}

          true ->
            {pid, %{sub | dirty: true}}
        end
      end)

    %{s | sequence: seq, subscribers: subscribers}
  end
end
