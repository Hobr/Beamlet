defmodule Beamlet.Storage.AgentRecords do
  @moduledoc """
  Atomic Agent transactions: creation with an initial checkpoint, accepted input,
  exactly-once result consumption and bounded reads. Each write validates its own
  identity, strict JSON schema, owning Agent/turn, current accepted Result, version
  and generation inside the transaction; nothing is trusted from the caller.
  `history_seq` and `lock_version` advance by CAS in the same transaction.
  """
  import Ecto.Query
  alias Beamlet.Storage.{Codec, Records, Transaction}
  alias Beamlet.Storage.Schema.{Agent, Checkpoint, Command, Event, Operation}

  @continuations ~w(await_input model_prepared tool_batch_prepared await_model_result await_tool_results reply_recorded results_to_consume ready_for_next_step await_delegation await_peer interrupted blocked completed)
  @consumption_kinds ~w(tool_result model_result evidence_resolution)
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
