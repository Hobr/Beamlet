defmodule Beamlet.Agent.Storage.AgentRecords do
  @moduledoc "Agent inputs and reference-only orchestration, atomically committed with prepared work."
  alias Beamlet.Agent.Storage.Read
  alias Beamlet.Agent.Storage.Schema.AgentOperation
  alias Beamlet.Storage.References
  import Ecto.Query

  alias Beamlet.Actions.Storage.DispatchScopes
  alias Beamlet.Actions.Storage.OperationRecords, as: Actions
  alias Beamlet.Agent.Storage.Codec
  alias Beamlet.Agent.Storage.Events
  alias Beamlet.Agent.Storage.History
  alias Beamlet.Agent.Storage.Inheritance
  alias Beamlet.Agent.Storage.OperationRecords
  alias Beamlet.Agent.Storage.Records
  alias Beamlet.Agent.Storage.Schema.Agent
  alias Beamlet.Agent.Storage.Schema.Checkpoint
  alias Beamlet.Agent.Storage.Schema.Command
  alias Beamlet.Agent.Storage.Schema.Event
  alias Beamlet.Agent.Storage.Schema.Operation
  alias Ecto.Adapters.SQL

  def create_agent(repo, attrs) do
    with {:ok, _} <-
           Records.fields(attrs, [:command_id, :id, :authority_id, :definition], [:alias]),
         {:ok, _} <- Records.uuid(attrs.command_id),
         {:ok, _} <- Records.uuid(attrs.id),
         {:ok, _} <- Records.uuid(attrs.authority_id),
         {:ok, _} <- Records.optional_text(attrs[:alias], 255),
         {:ok, _} <- Records.json(attrs.definition, :operation) do
      command(repo, attrs.id, attrs.command_id, attrs, fn -> create(repo, attrs) end)
    end
  end

  defp create(repo, attrs) do
    with :ok <- authority(repo, attrs.authority_id),
         :ok <- References.verify(repo, attrs.definition),
         {:ok, scope} <- DispatchScopes.create_in_transaction(repo, %{id: Ecto.UUID.generate()}),
         {:ok, agent} <-
           Records.insert(
             repo,
             Agent.changeset(%Agent{}, %{
               id: attrs.id,
               authority_id: attrs.authority_id,
               dispatch_scope_id: scope["id"],
               alias: attrs[:alias],
               definition: attrs.definition,
               generation: 0,
               lock_version: 0,
               history_seq: 1
             })
           ),
         {:ok, event} <-
           event(repo, agent.id, 1, "agent.created", %{"definition_version" => 1}, nil) do
      {:ok, response(agent, 0, 1, [event])}
    end
  end

  def accept_input(repo, attrs) do
    with {:ok, _} <- Records.fields(attrs, [:command_id, :position, :turn_id, :input], []),
         :ok <- validate_position(attrs.position),
         {:ok, _} <- Records.uuid(attrs.turn_id),
         {:ok, input} <- Records.json(attrs.input, :event),
         true <- is_map(input) and Map.keys(input) == ["text"] and is_binary(input["text"]),
         true <- byte_size(input["text"]) <= 65_536 and String.valid?(input["text"]) do
      transition(repo, attrs, fn agent -> input(repo, agent, attrs, input) end)
    else
      false -> {:error, :invalid_data}
      error -> error
    end
  end

  defp input(repo, agent, attrs, input) do
    case repo.one(
           from(e in Event,
             where:
               e.scope_id == ^agent.id and e.turn_id == ^attrs.turn_id and
                 e.type == "input.accepted"
           ),
           log: false
         ) do
      nil -> append(repo, agent, attrs.position, [{"input.accepted", input, attrs.turn_id}])
      _ -> {:error, :conflict}
    end
  end

  def prepare_operations(repo, attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [:command_id, :position, :turn_id, :operations, :orchestration],
             []
           ),
         :ok <- validate_position(attrs.position),
         {:ok, _} <- Records.uuid(attrs.turn_id),
         :ok <- Events.control(attrs.orchestration),
         {:ok, members} <- members(attrs.operations) do
      transition(repo, attrs, fn agent -> prepare(repo, agent, attrs, members) end)
    end
  end

  defp members(list) when is_list(list) and length(list) in 1..8 do
    Enum.reduce_while(list, {:ok, []}, fn member, {:ok, acc} ->
      with {:ok, _} <- Records.fields(member, [:operation, :attempt], []),
           {:ok, op} <- OperationRecords.validate_operation(member.operation),
           {:ok, attempt} <- OperationRecords.validate_attempt(member.attempt) do
        {:cont, {:ok, acc ++ [%{operation: op, attempt: attempt}]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp members(list) when is_list(list), do: {:error, :limit}
  defp members(_), do: {:error, :invalid_data}

  defp prepare(repo, agent, attrs, members) do
    with :ok <- active_turn(repo, agent.id, attrs.turn_id),
         :ok <- control_references(repo, agent, attrs.orchestration),
         :ok <- unique_members(members),
         {:ok, prepared} <- prepare_members(repo, agent, attrs, members),
         specs = preparation_specs(members, attrs),
         {:ok, response} <- append(repo, agent, attrs.position, specs) do
      {:ok, Map.put(response, "operations", prepared)}
    end
  end

  defp preparation_specs(members, attrs) do
    Enum.map(members, fn %{operation: op} ->
      type = if op.role == "tool", do: "tool.batch_prepared", else: "model.request_prepared"

      {type,
       %{
         "operation_id" => op.id,
         "step_id" => op.step_id,
         "ordinal" => op.ordinal,
         "join" => attrs.orchestration
       }, attrs.turn_id}
    end)
  end

  defp unique_members(members) do
    ids = Enum.map(members, & &1.operation.id)
    ordinals = Enum.map(members, & &1.operation.ordinal)

    if length(Enum.uniq(ids)) == length(ids) and length(Enum.uniq(ordinals)) == length(ordinals),
      do: :ok,
      else: {:error, :invalid_data}
  end

  defp prepare_members(repo, agent, attrs, members) do
    members
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {%{operation: op, attempt: attempt}, index}, {:ok, acc} ->
      with true <- op.owner_agent_id == agent.id and op.turn_id == attrs.turn_id,
           :ok <- verify_sources(repo, agent, op.sources),
           op =
             Map.merge(op, %{
               owner_generation: agent.generation,
               prepared_seq: agent.history_seq + index + 1
             }),
           {:ok, prepared} <-
             Actions.prepare_in_transaction(repo, %{
               operation: %{
                 id: op.id,
                 description: op.description,
                 dispatch_scope_id: agent.dispatch_scope_id,
                 dispatch_epoch: agent.generation
               },
               attempt: attempt
             }),
           {:ok, _} <- insert_association(repo, op) do
        {:cont, {:ok, acc ++ [prepared]}}
      else
        false -> {:halt, {:error, :conflict}}
        error -> {:halt, error}
      end
    end)
  end

  defp insert_association(repo, op) do
    fields =
      ~w(id owner_agent_id turn_id step_id role ordinal tool_call_id owner_generation prepared_seq sources)a

    Records.insert(
      repo,
      AgentOperation.changeset(
        %AgentOperation{},
        Map.take(op, fields)
      )
    )
  end

  def consume_results(repo, attrs) do
    with {:ok, _} <-
           Records.fields(attrs, [:command_id, :position, :turn_id, :accepted_refs, :join], []),
         :ok <- validate_position(attrs.position),
         {:ok, _} <- Records.uuid(attrs.turn_id),
         :ok <- Events.control(attrs.join),
         {:ok, _} <- Records.json(attrs.accepted_refs, :event),
         true <- is_list(attrs.accepted_refs) and length(attrs.accepted_refs) in 1..128 do
      transition(repo, attrs, fn agent -> consume(repo, agent, attrs) end)
    else
      false -> {:error, :invalid_data}
      error -> error
    end
  end

  defp consume(repo, agent, attrs) do
    with :ok <- active_turn(repo, agent.id, attrs.turn_id),
         :ok <- control_references(repo, agent, attrs.join),
         {:ok, refs} <- consumables(repo, agent, attrs),
         :ok <- unconsumed(repo, agent.id, refs) do
      specs =
        Enum.map(refs, fn ref ->
          {"operation.result_consumed", Map.put(ref, "join", attrs.join), attrs.turn_id}
        end)

      append(repo, agent, attrs.position, specs)
    end
  end

  defp consumables(repo, agent, attrs) do
    Enum.reduce_while(attrs.accepted_refs, {:ok, []}, fn ref, {:ok, acc} ->
      with :ok <- accepted_reference(repo, agent, ref),
           {:ok, op} <- Records.get(repo, Operation, ref["operation_id"]),
           true <- op.turn_id == attrs.turn_id and op.owner_generation == agent.generation,
           false <- Enum.any?(acc, &(&1["operation_id"] == ref["operation_id"])) do
        {:cont, {:ok, acc ++ [ref]}}
      else
        _ -> {:halt, {:error, :conflict}}
      end
    end)
  end

  defp unconsumed(repo, agent_id, refs) do
    keys = Enum.map(refs, &consumption_key/1)

    count =
      repo.one(
        from(e in Event,
          where: e.scope_id == ^agent_id and e.dedupe_key in ^keys,
          select: count(e.id)
        ),
        log: false
      )

    if count == 0, do: :ok, else: {:error, :conflict}
  end

  defp consumption_key(ref),
    do: "consume:" <> ref["operation_id"] <> ":" <> ref["consumption_kind"]

  # Source records are explicit, typed, bounded and same-authority. Only consumed
  # accepted Results can contribute to a later request.
  defp verify_sources(repo, agent, sources) do
    Enum.reduce_while(sources, :ok, fn source, :ok ->
      case source(repo, agent, source) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp source(
         repo,
         agent,
         %{"type" => "input", "event_id" => id, "seq" => seq, "digest" => digest} = ref
       )
       when map_size(ref) == 4 do
    case repo.get(Event, id, log: false) do
      %Event{scope_id: scope, seq: ^seq, type: "input.accepted", payload: payload}
      when scope == agent.id and seq <= agent.history_seq ->
        if Codec.digest(payload, :event) == {:ok, digest}, do: :ok, else: {:error, :conflict}

      _ ->
        {:error, :conflict}
    end
  end

  defp source(repo, agent, %{"type" => "accepted_result", "reference" => ref} = source)
       when map_size(source) == 2 do
    with :ok <- accepted_reference(repo, agent, ref),
         %Event{} <-
           repo.one(
             from(e in Event,
               where: e.scope_id == ^agent.id and e.dedupe_key == ^consumption_key(ref)
             ),
             log: false
           ) do
      :ok
    else
      _ -> {:error, :conflict}
    end
  end

  defp source(repo, agent, %{"type" => type} = ref)
       when type in ~w(inherited_input inherited_result) do
    if Inheritance.authorized?(repo, agent.id, ref, agent.history_seq),
      do: :ok,
      else: {:error, :conflict}
  end

  defp source(_, _, _), do: {:error, :invalid_data}

  defp accepted_reference(repo, agent, ref) when is_map(ref) and not is_struct(ref) do
    with true <- Enum.sort(Map.keys(ref)) == ~w(accepted_digest consumption_kind operation_id),
         {:ok, id} <- Records.uuid(ref["operation_id"]),
         {:ok, _} <- Records.digest(ref["accepted_digest"]),
         {:ok, _} <-
           Records.enum(ref["consumption_kind"], ~w(model_result tool_result evidence_resolution)),
         {:ok, op} <- Records.get(repo, Operation, id),
         true <- op.owner_agent_id == agent.id and not is_nil(op.accepted_result),
         true <- consumption_role?(op.role, ref["consumption_kind"]),
         {:ok, digest} <- Codec.digest(op.accepted_result, :result),
         true <- digest == ref["accepted_digest"] do
      :ok
    else
      _ -> {:error, :conflict}
    end
  end

  defp accepted_reference(_, _, _), do: {:error, :invalid_data}

  defp consumption_role?(_, "evidence_resolution"), do: true
  defp consumption_role?("tool", "tool_result"), do: true
  defp consumption_role?(role, "model_result") when role in ~w(model summary), do: true
  defp consumption_role?(_, _), do: false

  def checkpoint(repo, attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [
               :command_id,
               :position,
               :id,
               :through_seq,
               :reducer_version,
               :projection,
               :continuation,
               :safe_to_fork
             ],
             []
           ),
         :ok <- validate_position(attrs.position),
         {:ok, _} <- Records.uuid(attrs.id),
         {:ok, _} <- Records.count(attrs.through_seq),
         true <- is_integer(attrs.reducer_version) and attrs.reducer_version > 0,
         true <- is_boolean(attrs.safe_to_fork),
         :ok <- Events.control(attrs.projection),
         {:ok, digest} <- Codec.digest(attrs.projection, :checkpoint) do
      transition(repo, attrs, fn agent -> write_checkpoint(repo, agent, attrs, digest) end)
    else
      false -> {:error, :invalid_data}
      error -> error
    end
  end

  defp write_checkpoint(repo, agent, attrs, digest) do
    with :ok <- control_references(repo, agent, attrs.projection) do
      insert_checkpoint(repo, agent, attrs, digest)
    end
  end

  defp insert_checkpoint(repo, agent, attrs, digest) do
    if attrs.through_seq == agent.history_seq do
      cs =
        Checkpoint.changeset(%Checkpoint{}, %{
          id: attrs.id,
          agent_id: agent.id,
          through_seq: attrs.through_seq,
          reducer_version: attrs.reducer_version,
          data: attrs.projection,
          digest: digest,
          continuation: attrs.continuation,
          safe_to_fork: attrs.safe_to_fork,
          schema_version: 1,
          recorded_at: DateTime.utc_now()
        })

      with {:ok, _} <- Records.insert(repo, cs),
           {:ok, version} <-
             Records.cas_agent(
               repo,
               agent,
               attrs.position.lock_version,
               attrs.position.generation,
               head_checkpoint_id: attrs.id
             ) do
        {:ok, response(agent, version, agent.history_seq, [])}
      end
    else
      {:error, :conflict}
    end
  end

  defp control_references(repo, agent, map) when is_map(map) do
    with :ok <- control_operation(repo, agent, map),
         :ok <- References.verify(repo, map) do
      verify_control_children(repo, agent, Map.values(map))
    end
  end

  defp control_references(repo, agent, list) when is_list(list),
    do: verify_control_children(repo, agent, list)

  defp control_references(_, _, _), do: :ok

  defp verify_control_children(repo, agent, values) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case control_references(repo, agent, value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp control_operation(repo, agent, %{"operation_id" => id} = ref) do
    with {:ok, _} <- Records.uuid(id),
         {:ok, op} <- Records.get(repo, Operation, id),
         true <- op.owner_agent_id == agent.id or inherited_operation?(repo, agent, id) do
      control_digest(op, ref)
    else
      _ -> {:error, :conflict}
    end
  end

  defp control_operation(_, _, _), do: :ok

  defp inherited_operation?(repo, agent, id) do
    case repo.one(
           from(e in Event, where: e.scope_id == ^agent.id and e.type == "context.inherited"),
           log: false
         ) do
      %Event{payload: manifest} ->
        Enum.any?(
          manifest["closure"],
          &(&1["type"] == "inherited_result" and &1["reference"]["operation_id"] == id)
        ) and
          Inheritance.verify(repo, manifest) == :ok

      _ ->
        false
    end
  end

  defp control_digest(op, %{"accepted_digest" => digest}) do
    if not is_nil(op.accepted_result) and
         Codec.digest(op.accepted_result, :result) == {:ok, digest},
       do: :ok,
       else: {:error, :conflict}
  end

  defp control_digest(_, _), do: :ok

  def advance(repo, attrs) do
    with {:ok, _} <-
           Records.fields(attrs, [:command_id, :position, :turn_id, :type, :payload], []),
         :ok <- validate_position(attrs.position),
         {:ok, _} <- Records.optional_uuid(attrs.turn_id),
         true <-
           attrs.type in ~w(turn.interrupted agent.continue_decided agent.config_changed context.selected),
         :ok <- Events.control(attrs.payload) do
      transition(repo, attrs, &advance_control(repo, &1, attrs))
    else
      false -> {:error, :invalid_data}
      error -> error
    end
  end

  defp advance_control(repo, agent, attrs) do
    with :ok <- control_references(repo, agent, attrs.payload),
         :ok <- resume_operations(repo, agent, attrs) do
      append(repo, agent, attrs.position, [{attrs.type, attrs.payload, attrs.turn_id}])
    end
  end

  # Only an explicit continuation transaction may authorize a prior generation's
  # still-prepared work or its accepted output. Claimed unresolved work stays fenced.
  defp resume_operations(_repo, _agent, %{
         type: "agent.continue_decided",
         payload: %{"resume_operations" => []}
       }),
       do: :ok

  defp resume_operations(repo, agent, %{
         type: "agent.continue_decided",
         payload: %{"resume_operations" => ids},
         turn_id: turn
       })
       when is_list(ids) and length(ids) <= 8 do
    with :ok <- active_turn(repo, agent.id, turn) do
      resume_members(repo, agent, turn, ids)
    end
  end

  defp resume_operations(_, _, %{
         type: "agent.continue_decided",
         payload: %{"resume_operations" => _}
       }),
       do: {:error, :invalid_data}

  defp resume_operations(_, _, _), do: :ok

  defp resume_members(repo, agent, turn, ids) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case resume_operation(repo, agent, turn, id) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp resume_operation(repo, agent, turn, id) do
    with {:ok, op} <- Records.get(repo, Operation, id),
         true <- op.owner_agent_id == agent.id and op.turn_id == turn,
         {:ok, %{"attempt" => attempt}} <- OperationRecords.fetch(repo, id),
         :ok <- reauthorize(repo, agent, op, attempt) do
      repo.update_all(
        from(o in AgentOperation, where: o.id == ^id),
        [set: [owner_generation: agent.generation]],
        log: false
      )

      :ok
    else
      _ -> {:error, :unresolved_execution}
    end
  end

  defp reauthorize(_repo, _agent, %{accepted_result: result}, _) when not is_nil(result), do: :ok

  defp reauthorize(_repo, agent, %{dispatch_epoch: epoch}, %{"dispatch_state" => "prepared"})
       when epoch == agent.generation, do: :ok

  defp reauthorize(repo, agent, op, attempt) do
    case DispatchScopes.reauthorize_in_transaction(repo, %{
           scope_id: agent.dispatch_scope_id,
           from_epoch: op.dispatch_epoch,
           to_epoch: agent.generation,
           operation_id: op.id,
           attempt_id: attempt["attempt_id"],
           description_digest: op.description_digest,
           expected_version: op.lock_version,
           attempt_version: attempt["lock_version"]
         }) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc "Atomically materialize a same-authority reference manifest; source rows are never mutated."
  def fork(repo, attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [
               :command_id,
               :position,
               :id,
               :through_seq,
               :timeline,
               :inheritance,
               :resolutions,
               :fork_request,
               :risk
             ],
             []
           ),
         :ok <- validate_position(attrs.position),
         {:ok, _} <- Records.uuid(attrs.id),
         {:ok, _} <- Records.count(attrs.through_seq),
         true <- attrs.risk in [nil, "unconfirmed"],
         true <-
           is_map(attrs.fork_request) and is_map(attrs.resolutions) and is_map(attrs.inheritance),
         true <- is_list(attrs.timeline) and length(attrs.timeline) <= 128,
         true <-
           attrs.fork_request["through_seq"] == attrs.through_seq and
             attrs.fork_request["expected_version"] == attrs.position.lock_version,
         {:ok, _} <- Records.json(Records.plain(attrs), :command) do
      transition(repo, attrs, &fork_records(repo, &1, attrs))
    else
      false -> {:error, :invalid_data}
      error -> error
    end
  end

  defp fork_records(repo, agent, attrs) do
    with {:ok, agent} <- lock_fork_source(repo, agent.id, attrs.position),
         true <- attrs.through_seq <= agent.history_seq,
         :ok <- Inheritance.source_position(repo, agent.id, attrs),
         :ok <- References.verify(repo, agent.definition),
         {:ok, scope} <- DispatchScopes.create_in_transaction(repo, %{id: Ecto.UUID.generate()}),
         {:ok, manifest} <-
           Inheritance.build(repo, agent.id, attrs.timeline, attrs.inheritance, attrs.resolutions),
         {:ok, child} <-
           Records.insert(
             repo,
             Agent.changeset(%Agent{}, %{
               id: attrs.id,
               authority_id: agent.authority_id,
               dispatch_scope_id: scope["id"],
               definition: agent.definition,
               generation: 0,
               lock_version: 0,
               history_seq: 3,
               forked_from_agent_id: agent.id
             })
           ),
         {:ok, created} <-
           event(repo, child.id, 1, "agent.created", %{"definition_version" => 1}, nil),
         {:ok, forked} <-
           event(
             repo,
             child.id,
             2,
             "agent.forked",
             %{
               "source_agent_id" => agent.id,
               "through_seq" => attrs.through_seq,
               "risk" => attrs.risk
             },
             nil
           ),
         {:ok, inherited} <- inherited_event(repo, child.id, agent.id, manifest) do
      {:ok,
       Map.put(
         response(child, 0, 3, [created, forked, inherited]),
         "fork_request",
         attrs.fork_request
       )}
    else
      false -> {:error, :conflict}
      error -> error
    end
  end

  defp lock_fork_source(repo, id, pos) do
    query = from(a in Agent, where: a.id == ^id)

    query =
      if repo.__adapter__() == Ecto.Adapters.Postgres,
        do: from(a in query, lock: "FOR SHARE"),
        else: query

    with %Agent{} = agent <- repo.one(query, log: false),
         :ok <- position(agent, pos),
         do: {:ok, agent}
  end

  defp inherited_event(repo, child, source, manifest) do
    with {:ok, stored} <-
           Records.insert(
             repo,
             Records.event_changeset(%{
               id: Ecto.UUID.generate(),
               scope_id: child,
               seq: 3,
               type: "context.inherited",
               payload: manifest,
               source_agent_id: source,
               schema_version: Events.version(),
               recorded_at: DateTime.utc_now()
             })
           ),
         do: {:ok, Records.plain(stored)}
  end

  def restore(repo, attrs) do
    with {:ok, _} <- Records.fields(attrs, [:command_id, :position], []),
         :ok <- validate_position(attrs.position) do
      transition(repo, attrs, fn agent -> activate(repo, agent, attrs) end)
    end
  end

  defp activate(repo, agent, attrs) do
    seq = agent.history_seq + 1

    with {:ok, _} <-
           DispatchScopes.rotate_in_transaction(repo, %{
             id: agent.dispatch_scope_id,
             expected_epoch: agent.generation
           }),
         {:ok, version} <-
           Records.cas_agent(
             repo,
             agent,
             attrs.position.lock_version,
             attrs.position.generation,
             generation: agent.generation + 1,
             history_seq: seq,
             head_checkpoint_id: nil
           ),
         {:ok, event} <-
           event(
             repo,
             agent.id,
             seq,
             "agent.activated",
             %{"generation" => agent.generation + 1, "continuation" => "interrupted"},
             nil
           ) do
      {:ok, response(%{agent | generation: agent.generation + 1}, version, seq, [event])}
    end
  end

  defp transition(repo, attrs, fun) do
    with {:ok, _} <- Records.uuid(attrs.command_id) do
      command(repo, attrs.position.agent_id, attrs.command_id, attrs, fn ->
        load_transition(repo, attrs.position, fun)
      end)
    end
  end

  defp load_transition(repo, pos, fun) do
    with {:ok, agent} <- locked_agent(repo, pos.agent_id),
         :ok <- position(agent, pos),
         do: fun.(agent)
  end

  defp locked_agent(repo, id) do
    query = from(a in Agent, where: a.id == ^id)

    query =
      if repo.__adapter__() == Ecto.Adapters.Postgres,
        do: from(a in query, lock: "FOR UPDATE"),
        else: query

    case repo.one(query, log: false) do
      nil -> {:error, :conflict}
      agent -> {:ok, agent}
    end
  end

  defp validate_position(pos) do
    with {:ok, _} <- Records.fields(pos, [:agent_id, :lock_version, :generation], []),
         {:ok, _} <- Records.uuid(pos.agent_id),
         {:ok, _} <- Records.count(pos.lock_version),
         {:ok, _} <- Records.count(pos.generation),
         do: :ok
  end

  defp position(agent, pos) do
    cond do
      agent.generation != pos.generation -> {:error, :stale_generation}
      agent.lock_version != pos.lock_version -> {:error, :conflict}
      true -> :ok
    end
  end

  defp authority(repo, id) do
    case SQL.query!(
           repo,
           "SELECT dataset_id FROM storage_metadata WHERE id = 1",
           [],
           log: false
         ).rows do
      [[^id]] -> :ok
      _ -> {:error, :conflict}
    end
  end

  defp active_turn(repo, agent_id, turn_id) do
    latest =
      repo.one(
        from(e in Event,
          where: e.scope_id == ^agent_id and e.type == "input.accepted",
          order_by: [desc: e.seq],
          limit: 1
        ),
        log: false
      )

    if latest && latest.turn_id == turn_id, do: :ok, else: {:error, :conflict}
  end

  defp append(repo, agent, pos, specs) do
    with {:ok, version} <-
           Records.cas_agent(repo, agent, pos.lock_version, pos.generation,
             history_seq: agent.history_seq + length(specs)
           ),
         {:ok, events} <- append_events(repo, agent, specs) do
      {:ok, response(agent, version, agent.history_seq + length(specs), events)}
    end
  end

  defp append_events(repo, agent, specs) do
    specs
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {{type, payload, turn}, index}, {:ok, acc} ->
      case event(repo, agent.id, agent.history_seq + index, type, payload, turn) do
        {:ok, event} -> {:cont, {:ok, acc ++ [event]}}
        error -> {:halt, error}
      end
    end)
  end

  defp event(repo, scope, seq, type, payload, turn) do
    dedupe = if type == "operation.result_consumed", do: consumption_key(payload)

    cs =
      Records.event_changeset(%{
        id: Ecto.UUID.generate(),
        scope_id: scope,
        seq: seq,
        type: type,
        payload: payload,
        turn_id: turn,
        operation_id: payload["operation_id"],
        dedupe_key: dedupe,
        schema_version: Events.version(),
        recorded_at: DateTime.utc_now()
      })

    with {:ok, stored} <- Records.insert(repo, cs), do: {:ok, Records.plain(stored)}
  end

  defp response(agent, version, seq, events) do
    %{
      "agent_id" => agent.id,
      "generation" => agent.generation,
      "lock_version" => version,
      "through_seq" => seq,
      "history_seq" => seq,
      "events" => events
    }
  end

  defp command(repo, scope, id, attrs, fun) do
    with {:ok, digest} <- Codec.digest(Records.plain(attrs), :command) do
      Records.transact(repo, fn -> replay_command(repo, scope, id, digest, fun) end)
    end
  end

  defp replay_command(repo, scope, id, digest, fun) do
    case Records.command_lookup(repo, scope, id) do
      %Command{request_digest: ^digest, response: response} ->
        {:ok, response}

      %Command{} ->
        {:error, :conflict}

      nil ->
        with {:ok, response} <- fun.(),
             {:ok, _} <-
               Records.insert(
                 repo,
                 Records.command_changeset(%{
                   id: Ecto.UUID.generate(),
                   scope_id: scope,
                   command_id: id,
                   request_digest: digest,
                   response: response,
                   recorded_at: DateTime.utc_now()
                 })
               ) do
          {:ok, response}
        end
    end
  end

  def fetch(repo, id) do
    with {:ok, id} <- Records.uuid(id) do
      Read.read(fn -> read_agent(repo, id) end)
    end
  end

  defp read_agent(repo, id) do
    with {:ok, agent} <- Records.get(repo, Agent, id) do
      {:ok, %{"agent" => Records.plain(agent), "head_checkpoint" => nil}}
    end
  end

  @doc "Read a stable committed command response after an unknown write outcome."
  def command_response(repo, agent_id, command_id) do
    with {:ok, _} <- Records.uuid(agent_id),
         {:ok, _} <- Records.uuid(command_id) do
      Read.read(fn -> read_command(repo, agent_id, command_id) end)
    end
  end

  defp read_command(repo, agent_id, command_id) do
    case Records.command_lookup(repo, agent_id, command_id) do
      nil -> {:error, :conflict}
      command -> {:ok, command.response}
    end
  end

  def history_page(repo, id, opts \\ []), do: History.event_page(repo, id, opts)
end
