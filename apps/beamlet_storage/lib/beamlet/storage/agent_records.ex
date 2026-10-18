defmodule Beamlet.Storage.AgentRecords do
  @moduledoc """
  Atomic Agent transactions: creation with an initial checkpoint, accepted input,
  exactly-once result consumption and bounded reads. Each write validates its own
  identity, strict JSON schema, owning Agent/turn, current accepted Result, version
  and generation inside the transaction; nothing is trusted from the caller.
  `history_seq` and `lock_version` advance by CAS in the same transaction.
  """
  import Ecto.Query
  alias Beamlet.Storage.{Artifacts, Codec, Records, Transaction}
  alias Beamlet.Storage.Schema.{Agent, Checkpoint, Command, Event, Operation}

  @continuations ~w(await_input model_prepared tool_batch_prepared await_model_result await_tool_results reply_recorded results_to_consume ready_for_next_step await_delegation await_peer interrupted blocked completed)
  @consumption_kinds ~w(tool_result model_result evidence_resolution)
  # A fork copies only a boundary where nothing of the source turn is still in
  # flight: no reply awaiting a batch, no results waiting to be consumed.
  # Checkpoints that carry a complete, copyable message boundary.
  @fork_idle ~w(await_input await_model_result completed)
  # ...of which only these are actually quiet: a mid-turn checkpoint may be copied
  # for inspection, but forking it needs a frozen source.
  @fork_quiet ~w(await_input completed)
  @fork_source_freezes ~w(frozen idle)a
  @fork_source_environments ~w(confirmed_stopped unconfirmed)a
  @risk_states ~w(uncertain deadline cancelled unknown)
  @max_messages 128
  @max_fork_bytes 1_048_576
  @fork_evidence_limit 256
  @max_consumptions 128
  @page_default 100
  @page_max 500
  @page_bytes 4_194_304

  def create_agent(repo, attrs) do
    with {:ok, input} <- validate_create(attrs) do
      Records.transact(repo, fn -> write_create(repo, input) end)
    end
  end

  def accept_input(repo, attrs) do
    with {:ok, input} <- validate_input(attrs) do
      Records.transact(repo, fn -> write_input(repo, input) end)
    end
  end

  def consume_result(repo, attrs) do
    with {:ok, input} <- validate_consume(attrs) do
      Records.transact(repo, fn -> write_consume(repo, input) end)
    end
  end

  @doc """
  Copies one immutable checkpoint of `source_agent_id` into a new independent Agent
  in one authority transaction: the Agent row (with `forked_from_*` provenance
  only), the inherited context records (fresh record ids plus source markers), the
  new `await_input` checkpoint, the fork event and the command response.

  Only a `safe_to_fork` checkpoint on a complete message boundary is accepted: no
  pending/join state, no unconsumed model reply or Tool result, no blocked turn and
  a complete Tool-call/result pairing. A source with undecided work in flight
  requires `source.freeze == :frozen`; an unconfirmed stop is recorded on the new
  Agent as `environment.risk == "unconfirmed"` so it may not execute until an
  explicit acceptance. A copy larger than `@max_fork_bytes` is refused, never
  truncated. Nothing of the source is read outside the transaction or referenced
  by the new Agent afterwards.
  """
  def fork(repo, attrs) do
    with {:ok, input} <- validate_fork(attrs) do
      Records.transact(repo, fn -> write_fork(repo, input) end)
    end
  end

  @doc """
  Advances the active turn's checkpoint (model reply, decision, blocked state)
  without consuming results or starting a turn. A supplied `command` makes the
  advance idempotent: replaying the same command identity and params returns the
  stored response and writes nothing.
  """
  def advance(repo, attrs) do
    with {:ok, input} <- validate_advance(attrs) do
      Records.transact(repo, fn -> write_advance(repo, input) end)
    end
  end

  @doc """
  Creates the paused instance's generation: CAS on `generation`+`lock_version`
  bumps the Agent generation, moves the head to the restored checkpoint, records
  the event and the restore command in one transaction. Concurrent restores and
  late writes from a previous generation lose the CAS.
  """
  def restore(repo, attrs) do
    with {:ok, input} <- validate_restore(attrs) do
      Records.transact(repo, fn -> write_restore(repo, input) end)
    end
  end

  @doc "Validates one next-checkpoint input for a batch transaction owned elsewhere."
  def checkpoint(attrs), do: next_checkpoint(attrs)

  @doc "Insert one checkpoint inside the caller's open transaction."
  def insert_checkpoint(repo, checkpoint, agent_id, turn_id) do
    Records.insert(repo, checkpoint_changeset(checkpoint, agent_id, turn_id))
  end

  def fetch(repo, agent_id) do
    with {:ok, id} <- Records.uuid(agent_id) do
      Transaction.read(fn ->
        case repo.get(Agent, id, log: false) do
          nil ->
            {:error, :conflict}

          agent ->
            {:ok,
             %{
               "agent" => Records.plain(agent),
               "head_checkpoint" => Records.plain(head_checkpoint(repo, agent))
             }}
        end
      end)
    end
  end

  def history_page(repo, agent_id, opts \\ []) do
    with {:ok, id} <- Records.uuid(agent_id),
         {:ok, after_seq, limit} <- page_opts(opts) do
      Transaction.read(fn -> read_page(repo, id, after_seq, limit) end)
    end
  end

  ## Creation

  defp validate_create(attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [:command, :id, :authority_id, :definition, :generation, :checkpoint, :event],
             [:alias, :forked_from_agent_id, :forked_from_checkpoint_id]
           ),
         {:ok, command} <- command(attrs[:command]),
         {:ok, id} <- Records.uuid(attrs[:id]),
         {:ok, authority_id} <- Records.uuid(attrs[:authority_id]),
         {:ok, alias_name} <- Records.optional_text(attrs[:alias], 255),
         {:ok, definition} <- Records.json(attrs[:definition], :operation),
         {:ok, 0} <- Records.count(attrs[:generation]),
         {:ok, forked_agent} <- Records.optional_uuid(attrs[:forked_from_agent_id]),
         {:ok, forked_checkpoint} <- Records.optional_uuid(attrs[:forked_from_checkpoint_id]),
         {:ok, checkpoint} <- initial_checkpoint(attrs[:checkpoint]),
         {:ok, event} <- Records.event_input(attrs[:event]) do
      {:ok,
       %{
         command: command,
         agent: %{
           id: id,
           authority_id: authority_id,
           alias: alias_name,
           definition: definition,
           forked_from_agent_id: forked_agent,
           forked_from_checkpoint_id: forked_checkpoint
         },
         checkpoint: checkpoint,
         event: event
       }}
    else
      {:ok, _generation} -> {:error, :invalid_data}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_create(repo, input) do
    case replay(repo, input.command) do
      {:ok, {:stored, response}} -> {:ok, response}
      {:ok, :new} -> insert_create(repo, input)
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_create(repo, input) do
    agent = input.agent
    checkpoint = input.checkpoint
    seq = 1

    with {:ok, _agent} <- Records.insert(repo, agent_changeset(agent)),
         {:ok, _checkpoint} <-
           Records.insert(repo, checkpoint_changeset(checkpoint, agent.id, nil)),
         {:ok, _} <- set_head(repo, agent.id, checkpoint.id),
         {:ok, _event} <- Records.insert(repo, event_changeset(input.event, agent.id, seq, %{})),
         response = %{
           "agent_id" => agent.id,
           "checkpoint_id" => checkpoint.id,
           "command_id" => input.command.command_id,
           "history_seq" => seq,
           "lock_version" => 0
         },
         {:ok, _command} <- insert_command(repo, input.command, response) do
      {:ok, response}
    end
  end

  defp agent_changeset(agent) do
    Agent.changeset(%Agent{}, %{
      id: agent.id,
      authority_id: agent.authority_id,
      alias: agent.alias,
      definition: agent.definition,
      generation: 0,
      lock_version: 0,
      history_seq: 1,
      forked_from_agent_id: agent.forked_from_agent_id,
      forked_from_checkpoint_id: agent.forked_from_checkpoint_id
    })
    |> Ecto.Changeset.unique_constraint([:authority_id, :alias],
      name: :agents_authority_id_alias_index
    )
  end

  defp set_head(repo, agent_id, checkpoint_id) do
    query =
      from(a in Agent,
        where: a.id == ^agent_id,
        update: [set: [head_checkpoint_id: ^checkpoint_id]]
      )

    case repo.update_all(query, [], log: false) do
      {1, _} -> {:ok, checkpoint_id}
      {0, _} -> {:error, :conflict}
    end
  end

  ## Fork

  defp validate_fork(attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [
               :command,
               :id,
               :authority_id,
               :source_agent_id,
               :checkpoint_id,
               :expected_version,
               :new_checkpoint_id,
               :source,
               :data,
               :event
             ],
             [:alias]
           ),
         {:ok, command} <- command(attrs[:command]),
         {:ok, id} <- Records.uuid(attrs[:id]),
         {:ok, new_checkpoint_id} <- Records.uuid(attrs[:new_checkpoint_id]),
         {:ok, authority_id} <- Records.uuid(attrs[:authority_id]),
         {:ok, alias_name} <- Records.optional_text(attrs[:alias], 255),
         {:ok, source_agent_id} <- Records.uuid(attrs[:source_agent_id]),
         {:ok, checkpoint_id} <- Records.uuid(attrs[:checkpoint_id]),
         {:ok, version} <- Records.count(attrs[:expected_version]),
         {:ok, source} <- fork_source(attrs[:source]),
         {:ok, data} <- Records.json(attrs[:data], :checkpoint),
         {:ok, event} <- Records.event_input(attrs[:event]) do
      {:ok,
       %{
         command: command,
         id: id,
         new_checkpoint_id: new_checkpoint_id,
         authority_id: authority_id,
         alias: alias_name,
         source_agent_id: source_agent_id,
         checkpoint_id: checkpoint_id,
         expected_version: version,
         source: source,
         data: data,
         event: event
       }}
    end
  end

  defp fork_source(source) when is_map(source) and not is_struct(source) do
    with {:ok, _} <- Records.fields(source, [:freeze, :environment], []),
         true <- source[:freeze] in @fork_source_freezes,
         true <- source[:environment] in @fork_source_environments do
      {:ok, %{freeze: source[:freeze], environment: source[:environment]}}
    else
      _ -> {:error, :invalid_data}
    end
  end

  defp fork_source(_), do: {:error, :invalid_data}

  defp write_fork(repo, input) do
    case replay(repo, input.command) do
      {:ok, {:stored, response}} -> {:ok, response}
      {:ok, :new} -> insert_fork(repo, input)
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_fork(repo, input) do
    with {:ok, source} <- Records.get(repo, Agent, input.source_agent_id),
         :ok <- same_authority(source, input.authority_id),
         :ok <- source_version(source, input.expected_version),
         {:ok, checkpoint} <- fork_checkpoint(repo, input),
         {:ok, messages} <- fork_messages(checkpoint["data"]),
         :ok <- fork_freeze(repo, source, checkpoint, input.source),
         {:ok, risk} <- fork_risk(repo, source, input.source),
         {:ok, definition} <- fork_definition(repo, source),
         :ok <- fork_size(messages, definition),
         seq = length(messages) + 1,
         {:ok, _agent} <- Records.insert(repo, fork_agent_changeset(input, definition, seq)),
         data = fork_data(input, checkpoint, messages, risk),
         {:ok, checkpoint_digest} <- digest_of(data, :checkpoint),
         {:ok, _checkpoint} <-
           Records.insert(
             repo,
             checkpoint_changeset(
               %{
                 id: input.new_checkpoint_id,
                 data: data,
                 continuation: "await_input",
                 digest: checkpoint_digest,
                 safe_to_fork: true
               },
               input.id,
               nil
             )
           ),
         {:ok, _} <- set_head(repo, input.id, input.new_checkpoint_id),
         {:ok, _event} <- Records.insert(repo, fork_event_changeset(input, source, risk)),
         {:ok, inherited} <- insert_inherited(repo, input, messages),
         response = fork_response(input, risk, seq, messages, inherited),
         {:ok, _command} <- insert_command(repo, input.command, response) do
      {:ok, response}
    end
  end

  defp same_authority(source, authority_id) do
    if source.authority_id == authority_id, do: :ok, else: {:error, :invalid_data}
  end

  # The expected version is the caller's proof it saw the source state it is
  # branching from; a fork never writes to the source, so it is a check, not a CAS.
  defp source_version(source, expected) do
    if source.lock_version == expected, do: :ok, else: {:error, :conflict}
  end

  defp fork_checkpoint(repo, input) do
    with {:ok, %Checkpoint{} = checkpoint} <- Records.get(repo, Checkpoint, input.checkpoint_id),
         true <- checkpoint.agent_id == input.source_agent_id,
         true <- checkpoint.safe_to_fork == true,
         true <- checkpoint.continuation in @fork_idle do
      {:ok, Records.plain(checkpoint)}
    else
      _ -> {:error, :unsafe_checkpoint}
    end
  end

  defp fork_messages(%{"messages" => messages} = data) do
    with true <- is_list(messages),
         :ok <- fork_message_count(messages),
         :ok <- fork_boundary(data),
         :ok <- complete_pairing(messages) do
      {:ok, messages}
    else
      {:error, :limit} = error -> error
      _ -> {:error, :unsafe_checkpoint}
    end
  end

  defp fork_messages(_), do: {:error, :unsafe_checkpoint}

  defp fork_message_count(messages) when length(messages) <= @max_messages, do: :ok
  defp fork_message_count(_messages), do: {:error, :limit}

  defp fork_boundary(data) do
    cond do
      Map.get(data, "pending") != [] -> {:error, :unsafe_checkpoint}
      Map.get(data, "order") != [] -> {:error, :unsafe_checkpoint}
      Map.get(data, "results") != %{} -> {:error, :unsafe_checkpoint}
      Map.get(data, "assistant") != nil -> {:error, :unsafe_checkpoint}
      Map.get(data, "blocked") != nil -> {:error, :unsafe_checkpoint}
      true -> :ok
    end
  end

  # Every Tool call is answered exactly once, in call order, and no Tool message
  # answers an unknown call: a copied context is therefore model-valid.
  defp complete_pairing(messages) do
    Enum.reduce_while(messages, {:ok, []}, fn message, {:ok, pending} ->
      case pairing_step(message, pending) do
        {:ok, next} -> {:cont, {:ok, next}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, []} -> :ok
      _ -> {:error, :unsafe_checkpoint}
    end
  end

  defp pairing_step(%{"role" => "tool", "call_id" => call_id}, [call_id | rest]), do: {:ok, rest}

  defp pairing_step(%{"role" => "assistant", "calls" => calls}, []) when is_list(calls) do
    ids =
      Enum.map(calls, fn
        %{"id" => id} when is_binary(id) -> id
        _ -> nil
      end)

    if Enum.all?(ids) and length(Enum.uniq(ids)) == length(ids),
      do: {:ok, ids},
      else: :error
  end

  defp pairing_step(%{"role" => role}, []) when role in ~w(system user assistant), do: {:ok, []}
  defp pairing_step(_, _), do: :error

  defp fork_freeze(repo, source, checkpoint, source_input) do
    working? =
      Map.get(checkpoint, "continuation") not in @fork_quiet or
        undecided_turn?(repo, source.id, checkpoint)

    if working? and source_input.freeze != :frozen,
      do: {:error, :source_not_frozen},
      else: :ok
  end

  # Only Operations of the head checkpoint's own turn can be in flight. An Operation
  # an explicit decision already abandoned keeps a NULL accepted_result forever and
  # must not make every later fork of an otherwise idle Agent fail.
  defp undecided_turn?(repo, source_agent_id, checkpoint) do
    case Map.get(checkpoint, "turn_id") do
      turn_id when is_binary(turn_id) ->
        query =
          from(o in Operation,
            where:
              o.owner_agent_id == ^source_agent_id and o.turn_id == ^turn_id and
                is_nil(o.accepted_result),
            select: count(o.id)
          )

        repo.one(query, log: false) > 0

      _ ->
        false
    end
  end

  # An unconfirmed stop is a risk, and so is any accepted Result the source never
  # resolved: either way the copied context does not prove the shared environment
  # stopped changing.
  defp fork_risk(repo, source, source_input) do
    if source_input.environment == :unconfirmed or risky_result?(repo, source.id),
      do: {:ok, "unconfirmed"},
      else: {:ok, nil}
  end

  # A scan that cannot see every accepted Result must assume risk: the safe
  # direction for an unverified shared environment is "unconfirmed".
  defp risky_result?(repo, source_agent_id) do
    total =
      from(o in Operation,
        where: o.owner_agent_id == ^source_agent_id and not is_nil(o.accepted_result),
        select: count(o.id)
      )
      |> repo.one(log: false)

    if total > @fork_evidence_limit do
      true
    else
      from(o in Operation,
        where: o.owner_agent_id == ^source_agent_id and not is_nil(o.accepted_result),
        order_by: [desc: o.history_seq],
        select: o.accepted_result
      )
      |> repo.all(log: false)
      |> Enum.any?(fn result ->
        String.Chars.to_string(get_in(result, ["status"])) in @risk_states
      end)
    end
  end

  defp fork_definition(repo, %Agent{definition: definition}) when is_map(definition) do
    with :ok <- Artifacts.verify_references(repo, artifact_ids(definition)) do
      {:ok, definition}
    end
  end

  defp artifact_ids(definition) do
    definition
    |> Map.get("tools", %{})
    |> Enum.flat_map(fn
      {_name, reference} when is_map(reference) -> Map.get(reference, "artifact_refs", [])
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp fork_size(messages, definition) do
    case Codec.encode(%{"messages" => messages, "definition" => definition}, :checkpoint) do
      {:ok, bytes} when byte_size(bytes) <= @max_fork_bytes -> :ok
      {:ok, _bytes} -> {:error, :limit}
      {:error, :limit} -> {:error, :limit}
      {:error, _reason} -> {:error, :invalid_data}
    end
  end

  defp fork_agent_changeset(input, definition, seq) do
    Agent.changeset(%Agent{}, %{
      id: input.id,
      authority_id: input.authority_id,
      alias: input.alias,
      definition: definition,
      generation: 0,
      lock_version: 0,
      history_seq: seq,
      forked_from_agent_id: input.source_agent_id,
      forked_from_checkpoint_id: input.checkpoint_id
    })
    |> Ecto.Changeset.unique_constraint([:authority_id, :alias],
      name: :agents_authority_id_alias_index
    )
  end

  defp fork_data(input, checkpoint, messages, risk) do
    Map.merge(input.data, %{
      "messages" => messages,
      "continuation" => "await_input",
      "turn_id" => nil,
      "step" => 0,
      "pending" => [],
      "order" => [],
      "results" => %{},
      "assistant" => nil,
      "blocked" => nil,
      "consumed" => [],
      "request_digest" => nil,
      "fork" => %{
        "source_agent_id" => input.source_agent_id,
        "source_checkpoint_id" => checkpoint["id"],
        "source_version" => input.expected_version,
        "inherited_messages" => length(messages)
      },
      "environment" => %{
        "source_agent_id" => input.source_agent_id,
        "source_checkpoint_id" => checkpoint["id"],
        "freeze" => Atom.to_string(input.source.freeze),
        "environment" => Atom.to_string(input.source.environment),
        "risk" => risk
      }
    })
  end

  defp fork_event_changeset(input, source, risk) do
    payload = %{
      "source_agent_id" => source.id,
      "source_checkpoint_id" => input.checkpoint_id,
      "source_version" => input.expected_version,
      "freeze" => Atom.to_string(input.source.freeze),
      "environment" => Atom.to_string(input.source.environment),
      "risk" => risk
    }

    event_changeset(input.event, input.id, 1, %{})
    |> Ecto.Changeset.change(payload: payload)
  end

  defp insert_inherited(repo, input, messages) do
    messages
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {message, index}, {:ok, acc} ->
      attrs = %{
        "index" => index,
        "role" => Map.get(message, "role"),
        "source_agent_id" => input.source_agent_id,
        "source_checkpoint_id" => input.checkpoint_id
      }

      case Records.insert(repo, inherited_changeset(input, index, attrs)) do
        {:ok, event} -> {:cont, {:ok, [event.id | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      error -> error
    end
  end

  defp inherited_changeset(input, index, payload) do
    Records.event_changeset(%{
      id: Ecto.UUID.generate(),
      scope_id: input.id,
      seq: index + 2,
      type: "context.inherited",
      schema_version: 1,
      payload: payload,
      source_agent_id: input.source_agent_id,
      recorded_at: DateTime.utc_now()
    })
  end

  defp fork_response(input, risk, seq, messages, inherited) do
    %{
      "agent_id" => input.id,
      "checkpoint_id" => input.new_checkpoint_id,
      "source_agent_id" => input.source_agent_id,
      "source_checkpoint_id" => input.checkpoint_id,
      "command_id" => input.command.command_id,
      "lock_version" => 0,
      "history_seq" => seq,
      "risk" => risk,
      "copied" => %{"messages" => length(messages), "records" => length(inherited)}
    }
  end

  ## Input acceptance

  defp validate_input(attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [
               :command,
               :agent_id,
               :expected_version,
               :expected_generation,
               :turn_id,
               :checkpoint,
               :event
             ],
             []
           ),
         {:ok, command} <- command(attrs[:command]),
         {:ok, agent_id} <- Records.uuid(attrs[:agent_id]),
         {:ok, version} <- Records.count(attrs[:expected_version]),
         {:ok, generation} <- Records.count(attrs[:expected_generation]),
         {:ok, turn_id} <- Records.uuid(attrs[:turn_id]),
         {:ok, checkpoint} <- next_checkpoint(attrs[:checkpoint]),
         {:ok, event} <- Records.event_input(attrs[:event]) do
      {:ok,
       %{
         command: command,
         agent_id: agent_id,
         expected_version: version,
         expected_generation: generation,
         turn_id: turn_id,
         checkpoint: checkpoint,
         event: event
       }}
    end
  end

  defp write_input(repo, input) do
    case replay(repo, input.command) do
      {:ok, {:stored, response}} ->
        {:ok, response}

      {:ok, :new} ->
        with {:ok, agent} <- Records.get(repo, Agent, input.agent_id),
             :ok <- current_generation(agent, input.expected_generation),
             :ok <- fresh_turn(repo, agent, input.turn_id),
             seq = agent.history_seq + 1,
             {:ok, _checkpoint} <-
               Records.insert(
                 repo,
                 checkpoint_changeset(input.checkpoint, agent.id, input.turn_id)
               ),
             {:ok, version} <-
               Records.cas_agent(
                 repo,
                 agent,
                 input.expected_version,
                 input.expected_generation,
                 head_checkpoint_id: input.checkpoint.id,
                 history_seq: seq
               ),
             {:ok, _event} <-
               Records.insert(
                 repo,
                 event_changeset(input.event, agent.id, seq, %{turn_id: input.turn_id})
               ),
             response = %{
               "agent_id" => agent.id,
               "checkpoint_id" => input.checkpoint.id,
               "turn_id" => input.turn_id,
               "command_id" => input.command.command_id,
               "history_seq" => seq,
               "lock_version" => version
             },
             {:ok, _command} <- insert_command(repo, input.command, response) do
          {:ok, response}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fresh_turn(repo, agent, turn_id) do
    case head_checkpoint(repo, agent) do
      nil -> :ok
      %Checkpoint{turn_id: ^turn_id} -> {:error, :conflict}
      %Checkpoint{} -> :ok
    end
  end

  ## Result consumption

  defp validate_consume(attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [
               :agent_id,
               :expected_version,
               :expected_generation,
               :turn_id,
               :operations,
               :checkpoint
             ],
             []
           ),
         {:ok, agent_id} <- Records.uuid(attrs[:agent_id]),
         {:ok, version} <- Records.count(attrs[:expected_version]),
         {:ok, generation} <- Records.count(attrs[:expected_generation]),
         {:ok, turn_id} <- Records.uuid(attrs[:turn_id]),
         {:ok, operations} <- consumptions(attrs[:operations]),
         {:ok, checkpoint} <- next_checkpoint(attrs[:checkpoint]) do
      {:ok,
       %{
         agent_id: agent_id,
         expected_version: version,
         expected_generation: generation,
         turn_id: turn_id,
         operations: operations,
         checkpoint: checkpoint
       }}
    end
  end

  defp consumptions(list) when is_list(list) and length(list) in 1..@max_consumptions do
    Enum.reduce_while(list, {:ok, []}, fn requested, {:ok, acc} ->
      with {:ok, _} <- Records.fields(requested, [:operation_id, :consumption_kind], []),
           {:ok, operation_id} <- Records.uuid(requested[:operation_id]),
           {:ok, kind} <- Records.enum(requested[:consumption_kind], @consumption_kinds),
           false <- Enum.any?(acc, &(&1.operation_id == operation_id)) do
        {:cont, {:ok, [%{operation_id: operation_id, kind: kind} | acc]}}
      else
        true -> {:halt, {:error, :invalid_data}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp consumptions(list) when is_list(list), do: {:error, :limit}
  defp consumptions(_), do: {:error, :invalid_data}

  defp write_consume(repo, input) do
    with {:ok, agent} <- Records.get(repo, Agent, input.agent_id),
         :ok <- current_generation(agent, input.expected_generation),
         {:ok, _head} <- active_turn(repo, agent, input.turn_id),
         {:ok, operations} <- load_consumables(repo, input) do
      existing = existing_consumptions(repo, agent.id, operations)

      cond do
        map_size(existing) == length(operations) ->
          {:ok, replay_consumption(agent, operations, existing)}

        map_size(existing) == 0 ->
          consume(repo, input, agent, operations)

        true ->
          {:error, :conflict}
      end
    end
  end

  defp active_turn(repo, agent, turn_id) do
    case head_checkpoint(repo, agent) do
      %Checkpoint{turn_id: ^turn_id} -> {:ok, turn_id}
      _ -> {:error, :conflict}
    end
  end

  defp load_consumables(repo, input) do
    Enum.reduce_while(input.operations, {:ok, []}, fn requested, {:ok, acc} ->
      case consumable(repo, requested, input) do
        {:ok, loaded} -> {:cont, {:ok, [loaded | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, loaded} ->
        {:ok,
         Enum.sort_by(loaded, fn op ->
           {op.operation.ordinal || 1_000_000_000, op.operation.id}
         end)}

      error ->
        error
    end
  end

  defp consumable(repo, requested, input) do
    with {:ok, operation} <- Records.get(repo, Operation, requested.operation_id),
         :ok <- owned_by(operation, input),
         :ok <- accepted(operation) do
      {:ok, %{operation: operation, kind: requested.kind}}
    end
  end

  # A forked Agent must never consume the source Agent's work: ownership is the
  # durable boundary, not a caller promise.
  defp owned_by(operation, input) do
    if operation.owner_agent_id == input.agent_id and operation.turn_id == input.turn_id,
      do: :ok,
      else: {:error, :conflict}
  end

  defp accepted(%Operation{accepted_result: nil}), do: {:error, :conflict}
  defp accepted(%Operation{}), do: :ok

  defp existing_consumptions(repo, agent_id, operations) do
    keys = Enum.map(operations, &consumption_key(&1.operation.id, &1.kind))

    from(e in Event, where: e.scope_id == ^agent_id and e.dedupe_key in ^keys)
    |> repo.all(log: false)
    |> Map.new(fn event -> {event.dedupe_key, event} end)
  end

  defp consume(repo, input, agent, operations) do
    count = length(operations)
    seq = agent.history_seq

    with {:ok, _checkpoint} <-
           Records.insert(repo, checkpoint_changeset(input.checkpoint, agent.id, input.turn_id)),
         {:ok, version} <-
           Records.cas_agent(
             repo,
             agent,
             input.expected_version,
             input.expected_generation,
             head_checkpoint_id: input.checkpoint.id,
             history_seq: seq + count
           ),
         {:ok, consumed} <-
           insert_consumptions(repo, agent.id, input.turn_id, operations, seq + 1) do
      {:ok,
       %{
         "agent_id" => agent.id,
         "checkpoint_id" => input.checkpoint.id,
         "consumed" => consumed,
         "history_seq" => seq + count,
         "lock_version" => version
       }}
    end
  end

  defp insert_consumptions(repo, agent_id, turn_id, operations, first_seq) do
    Enum.reduce_while(Enum.with_index(operations), {:ok, []}, fn {operation, index}, {:ok, acc} ->
      seq = first_seq + index

      attrs = %{
        "operation_id" => operation.operation.id,
        "tool_call_id" => operation.operation.tool_call_id,
        "ordinal" => operation.operation.ordinal,
        "consumption_kind" => operation.kind,
        "result" => operation.operation.accepted_result,
        "evidence_id" => operation.operation.accepted_evidence_id
      }

      event = %{
        id: Ecto.UUID.generate(),
        type: "result.consumed",
        payload: attrs,
        causation_id: nil
      }

      extra = %{
        turn_id: turn_id,
        operation_id: operation.operation.id,
        dedupe_key: consumption_key(operation.operation.id, operation.kind)
      }

      case Records.insert(repo, event_changeset(event, agent_id, seq, extra)) do
        {:ok, stored} ->
          consumed = %{
            "operation_id" => operation.operation.id,
            "consumption_kind" => operation.kind,
            "event_id" => stored.id,
            "seq" => seq
          }

          {:cont, {:ok, [consumed | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, consumed} -> {:ok, Enum.reverse(consumed)}
      error -> error
    end
  end

  defp replay_consumption(agent, operations, existing) do
    consumed =
      Enum.map(operations, fn operation ->
        event = Map.fetch!(existing, consumption_key(operation.operation.id, operation.kind))

        %{
          "operation_id" => operation.operation.id,
          "consumption_kind" => operation.kind,
          "event_id" => event.id,
          "seq" => event.seq
        }
      end)

    %{
      "agent_id" => agent.id,
      "checkpoint_id" => agent.head_checkpoint_id,
      "consumed" => consumed,
      "history_seq" => agent.history_seq,
      "lock_version" => agent.lock_version
    }
  end

  defp consumption_key(operation_id, kind), do: "consume:" <> operation_id <> ":" <> kind

  ## Shared validation

  defp command(command) do
    with {:ok, _} <- Records.fields(command, [:scope_id, :command_id, :params], []),
         {:ok, scope_id} <- Records.uuid(command[:scope_id]),
         {:ok, command_id} <- Records.uuid(command[:command_id]),
         {:ok, params} <- Records.json(command[:params], :command),
         {:ok, digest} <- digest_of(params, :command) do
      {:ok, %{scope_id: scope_id, command_id: command_id, request_digest: digest, params: params}}
    end
  end

  defp initial_checkpoint(checkpoint) do
    with {:ok, _} <- Records.fields(checkpoint, [:id, :data, :safe_to_fork], []),
         {:ok, id} <- Records.uuid(checkpoint[:id]),
         {:ok, data} <- Records.json(checkpoint[:data], :checkpoint),
         true <- checkpoint[:safe_to_fork] == true,
         {:ok, digest} <- digest_of(data, :checkpoint) do
      {:ok,
       %{id: id, data: data, digest: digest, safe_to_fork: true, continuation: "await_input"}}
    else
      false -> {:error, :invalid_data}
      {:error, reason} -> {:error, reason}
    end
  end

  defp next_checkpoint(checkpoint) do
    with {:ok, _} <-
           Records.fields(checkpoint, [:id, :data, :continuation, :safe_to_fork], []),
         {:ok, id} <- Records.uuid(checkpoint[:id]),
         {:ok, data} <- Records.json(checkpoint[:data], :checkpoint),
         {:ok, continuation} <- Records.enum(checkpoint[:continuation], @continuations),
         true <- is_boolean(checkpoint[:safe_to_fork]),
         {:ok, digest} <- digest_of(data, :checkpoint) do
      {:ok,
       %{
         id: id,
         data: data,
         digest: digest,
         safe_to_fork: checkpoint[:safe_to_fork],
         continuation: continuation
       }}
    else
      false -> {:error, :invalid_data}
      {:error, reason} -> {:error, reason}
    end
  end

  defp digest_of(value, kind) do
    case Codec.digest(value, kind) do
      {:ok, digest} -> {:ok, digest}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_advance(attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [:agent_id, :expected_version, :expected_generation, :turn_id, :checkpoint, :event],
             [:command, :adoption]
           ),
         {:ok, agent_id} <- Records.uuid(attrs[:agent_id]),
         {:ok, version} <- Records.count(attrs[:expected_version]),
         {:ok, generation} <- Records.count(attrs[:expected_generation]),
         # A decision taken at a no-turn boundary (`await_input`) has no active
         # turn; a reply/batch advance always supplies one.
         {:ok, turn_id} <- Records.optional_uuid(attrs[:turn_id]),
         {:ok, checkpoint} <- next_checkpoint(attrs[:checkpoint]),
         {:ok, event} <- Records.event_input(attrs[:event]),
         {:ok, command} <- optional_command(attrs[:command]),
         {:ok, adoption} <- optional_adoption(attrs[:adoption]) do
      {:ok,
       %{
         agent_id: agent_id,
         expected_version: version,
         expected_generation: generation,
         turn_id: turn_id,
         checkpoint: checkpoint,
         event: event,
         command: command,
         adoption: adoption
       }}
    end
  end

  defp optional_command(nil), do: {:ok, nil}
  defp optional_command(command), do: command(command)

  # A decision that adopts a stored accepted Result names that Result by digest,
  # so the transaction refuses to advance on a Result it did not read.
  defp optional_adoption(nil), do: {:ok, nil}

  defp optional_adoption(adoption) when is_map(adoption) and not is_struct(adoption) do
    with {:ok, _} <- Records.fields(adoption, [:operation_id, :accepted_digest], []),
         {:ok, operation_id} <- Records.uuid(adoption[:operation_id]),
         {:ok, digest} <- Records.digest(adoption[:accepted_digest]) do
      {:ok, %{operation_id: operation_id, accepted_digest: digest}}
    end
  end

  defp optional_adoption(_), do: {:error, :invalid_data}

  defp write_advance(repo, %{command: nil} = input), do: insert_advance(repo, input, nil)

  defp write_advance(repo, input) do
    case replay(repo, input.command) do
      {:ok, {:stored, response}} -> {:ok, response}
      {:ok, :new} -> insert_advance(repo, input, input.command)
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_advance(repo, input, command) do
    with {:ok, agent} <- Records.get(repo, Agent, input.agent_id),
         :ok <- current_generation(agent, input.expected_generation),
         :ok <- adoption_owner(repo, agent, input.adoption),
         :ok <- turn_binding(repo, agent, input.turn_id),
         seq = agent.history_seq + 1,
         {:ok, _checkpoint} <-
           Records.insert(
             repo,
             checkpoint_changeset(input.checkpoint, agent.id, input.turn_id)
           ),
         {:ok, version} <-
           Records.cas_agent(
             repo,
             agent,
             input.expected_version,
             input.expected_generation,
             head_checkpoint_id: input.checkpoint.id,
             history_seq: seq
           ),
         {:ok, _event} <-
           Records.insert(
             repo,
             event_changeset(input.event, agent.id, seq, %{turn_id: input.turn_id})
           ) do
      response = %{
        "agent_id" => agent.id,
        "checkpoint_id" => input.checkpoint.id,
        "turn_id" => input.turn_id,
        "history_seq" => seq,
        "lock_version" => version
      }

      with {:ok, _command} <- insert_command(repo, command, response), do: {:ok, response}
    end
  end

  # Only an idle head may advance without a turn; a live turn keeps its binding so a
  # caller cannot drop the turn identity from an in-flight checkpoint.
  defp turn_binding(repo, agent, nil) do
    case head_checkpoint(repo, agent) do
      %Checkpoint{turn_id: nil} -> :ok
      _ -> {:error, :invalid_data}
    end
  end

  defp turn_binding(_repo, _agent, _turn_id), do: :ok

  defp adoption_owner(_repo, _agent, nil), do: :ok

  defp adoption_owner(repo, agent, adoption) do
    with {:ok, operation} <- Records.get(repo, Operation, adoption.operation_id) do
      cond do
        operation.owner_agent_id != agent.id -> {:error, :conflict}
        is_nil(operation.accepted_result) -> {:error, :conflict}
        true -> adopted_digest(operation, adoption)
      end
    else
      {:error, :conflict} -> {:error, :conflict}
    end
  end

  defp adopted_digest(operation, adoption) do
    case Codec.digest(operation.accepted_result, :result) do
      {:ok, digest} when digest == adoption.accepted_digest -> :ok
      _ -> {:error, :conflict}
    end
  end

  defp validate_restore(attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [
               :command,
               :agent_id,
               :expected_version,
               :expected_generation,
               :checkpoint,
               :event
             ],
             [:turn_id]
           ),
         {:ok, command} <- command(attrs[:command]),
         {:ok, agent_id} <- Records.uuid(attrs[:agent_id]),
         {:ok, version} <- Records.count(attrs[:expected_version]),
         {:ok, generation} <- Records.count(attrs[:expected_generation]),
         {:ok, turn_id} <- Records.optional_uuid(attrs[:turn_id]),
         {:ok, checkpoint} <- next_checkpoint(attrs[:checkpoint]),
         {:ok, event} <- Records.event_input(attrs[:event]) do
      {:ok,
       %{
         command: command,
         agent_id: agent_id,
         expected_version: version,
         expected_generation: generation,
         turn_id: turn_id,
         checkpoint: checkpoint,
         event: event
       }}
    end
  end

  defp write_restore(repo, input) do
    case replay(repo, input.command) do
      {:ok, {:stored, response}} ->
        {:ok, response}

      {:ok, :new} ->
        with {:ok, agent} <- Records.get(repo, Agent, input.agent_id),
             :ok <- current_generation(agent, input.expected_generation),
             seq = agent.history_seq + 1,
             {:ok, _checkpoint} <-
               insert_checkpoint(repo, input.checkpoint, agent.id, input.turn_id),
             {:ok, version} <-
               bump_generation(
                 repo,
                 agent,
                 input.expected_version,
                 input.expected_generation,
                 input.checkpoint.id,
                 seq
               ),
             {:ok, _event} <-
               Records.insert(repo, event_changeset(input.event, agent.id, seq, %{})),
             response = %{
               "agent_id" => agent.id,
               "checkpoint_id" => input.checkpoint.id,
               "generation" => input.expected_generation + 1,
               "history_seq" => seq,
               "lock_version" => version
             },
             {:ok, _command} <- insert_command(repo, input.command, response) do
          {:ok, response}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The generation bump is the cross-request serializer: a second restore and any
  # late write from the previous generation fail the same CAS and write nothing.
  defp bump_generation(repo, agent, expected_version, expected_generation, checkpoint_id, seq) do
    query =
      from(a in Agent,
        where:
          a.id == ^agent.id and a.generation == ^expected_generation and
            a.lock_version == ^expected_version,
        update: [
          set: [
            generation: ^(expected_generation + 1),
            lock_version: ^(expected_version + 1),
            head_checkpoint_id: ^checkpoint_id,
            history_seq: ^seq
          ]
        ]
      )

    case repo.update_all(query, [], log: false) do
      {1, _} -> {:ok, expected_version + 1}
      {0, _} -> {:error, :conflict}
    end
  end

  defp current_generation(agent, expected) do
    if agent.generation == expected, do: :ok, else: {:error, :stale_generation}
  end

  defp checkout_changeset(attrs) do
    Checkpoint.changeset(%Checkpoint{}, attrs)
    |> Ecto.Changeset.unique_constraint(:id, name: :checkpoints_pkey)
  end

  defp checkpoint_changeset(checkpoint, agent_id, turn_id) do
    checkout_changeset(%{
      id: checkpoint.id,
      agent_id: agent_id,
      turn_id: turn_id,
      data: checkpoint.data,
      continuation: checkpoint.continuation,
      schema_version: 1,
      digest: checkpoint.digest,
      safe_to_fork: checkpoint.safe_to_fork,
      recorded_at: DateTime.utc_now()
    })
  end

  defp event_changeset(event, scope_id, seq, extra) do
    Records.event_changeset(
      Map.merge(
        %{
          id: event.id,
          scope_id: scope_id,
          seq: seq,
          type: event.type,
          schema_version: 1,
          payload: event.payload,
          causation_id: event.causation_id,
          recorded_at: DateTime.utc_now()
        },
        extra
      )
    )
  end

  defp replay(repo, command) do
    case Records.command_lookup(repo, command.scope_id, command.command_id) do
      nil ->
        {:ok, :new}

      %Command{request_digest: digest, response: response} ->
        if digest == command.request_digest,
          do: {:ok, {:stored, response}},
          else: {:error, :conflict}
    end
  end

  defp insert_command(_repo, nil, _response), do: {:ok, nil}

  defp insert_command(repo, command, response) do
    Records.insert(
      repo,
      Records.command_changeset(%{
        id: Ecto.UUID.generate(),
        scope_id: command.scope_id,
        command_id: command.command_id,
        request_digest: command.request_digest,
        response: response,
        recorded_at: DateTime.utc_now()
      })
    )
  end

  defp head_checkpoint(_repo, %Agent{head_checkpoint_id: nil}), do: nil

  defp head_checkpoint(repo, %Agent{head_checkpoint_id: id}) do
    repo.get(Checkpoint, id, log: false)
  end

  ## Bounded reads

  defp page_opts(opts) do
    cond do
      not is_list(opts) or not Keyword.keyword?(opts) ->
        {:error, :invalid_data}

      Enum.any?(Keyword.keys(opts), &(&1 not in [:after_seq, :limit])) ->
        {:error, :invalid_data}

      true ->
        page_bounds(Keyword.get(opts, :after_seq, 0), Keyword.get(opts, :limit, @page_default))
    end
  end

  defp page_bounds(after_seq, limit)
       when is_integer(after_seq) and after_seq >= 0 and is_integer(limit) and
              limit in 1..@page_max,
       do: {:ok, after_seq, limit}

  defp page_bounds(after_seq, limit)
       when is_integer(after_seq) and after_seq >= 0 and is_integer(limit) and limit > @page_max,
       do: {:error, :limit}

  defp page_bounds(_, _), do: {:error, :invalid_data}

  defp read_page(repo, agent_id, after_seq, limit) do
    query =
      from(e in Event,
        where: e.scope_id == ^agent_id and e.seq > ^after_seq,
        order_by: [asc: e.seq],
        limit: ^limit,
        select: %{event: e, raw: fragment("CAST(? AS TEXT)", e.payload)}
      )

    rows = repo.all(query, log: false)

    case take_page(rows, 0, [], limit) do
      {:ok, events, cursor} ->
        {:ok, %{"events" => Enum.map(events, &Records.plain/1), "next_cursor" => cursor}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp take_page([], _bytes, events, _limit), do: {:ok, Enum.reverse(events), nil}

  defp take_page([row | rest], bytes, events, limit) do
    # `length()` counts characters in both adapters; the page budget is bytes, so
    # the canonical JSON text is measured in Elixir instead.
    size = byte_size(row.raw)

    cond do
      bytes + size > @page_bytes and events == [] ->
        {:error, :limit}

      bytes + size > @page_bytes ->
        {:ok, Enum.reverse(events), hd(events).seq}

      rest == [] ->
        acc = [row.event | events]
        cursor = if length(acc) == limit, do: row.event.seq, else: nil
        {:ok, Enum.reverse(acc), cursor}

      true ->
        take_page(rest, bytes + size, [row.event | events], limit)
    end
  end
end
