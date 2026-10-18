defmodule Beamlet.Storage.OperationRecords do
  @moduledoc "Immutable requests, single dispatch claims, evidence and Operation-scoped acceptance."
  import Ecto.Query
  alias Beamlet.Storage.{Artifacts, Codec, Records, References, Transaction}
  alias Beamlet.Storage.Schema.{Agent, Execution, ExecutionEvidence, Operation}

  @description_keys ~w(kind protocol_version payload refs budget claims safety)

  # Owned work is created only by AgentRecords.prepare_operations/2.
  def prepare(repo, attrs) do
    with {:ok, _} <- Records.fields(attrs, [:operation, :attempt], []),
         {:ok, operation} <- validate_operation(attrs.operation),
         true <- independent?(operation),
         {:ok, attempt} <- validate_attempt(attrs.attempt) do
      Records.transact(repo, fn -> prepare_independent(repo, operation, attempt) end)
    else
      false -> {:error, :invalid_data}
      error -> error
    end
  end

  defp independent?(operation) do
    Enum.all?(
      ~w(owner_agent_id turn_id step_id role ordinal tool_call_id)a,
      &is_nil(Map.fetch!(operation, &1))
    ) and operation.sources == []
  end

  defp prepare_independent(repo, operation, attempt) do
    case repo.get(Operation, operation.id, log: false) do
      nil ->
        insert_prepared(repo, operation, attempt)

      stored ->
        execution =
          repo.one(from(e in Execution, where: e.operation_id == ^operation.id), log: false)

        expected = Map.take(stored, Map.keys(operation))
        actual = Map.take(execution || %{}, Map.keys(attempt))

        if expected == operation and actual == attempt,
          do: {:ok, prepared_response(operation, attempt)},
          else: {:error, :conflict}
    end
  end

  @doc false
  def validate_operation(attrs) do
    with {:ok, _} <-
           Records.fields(attrs, [:id, :description, :sources], [
             :owner_agent_id,
             :turn_id,
             :step_id,
             :role,
             :ordinal,
             :tool_call_id
           ]),
         {:ok, id} <- Records.uuid(attrs.id),
         {:ok, description} <- description(attrs.description),
         {:ok, sources} <- Records.json(attrs.sources, :operation),
         true <- is_list(sources) and length(sources) <= 128,
         {:ok, owner} <- Records.optional_uuid(attrs[:owner_agent_id]),
         {:ok, turn} <- Records.optional_uuid(attrs[:turn_id]),
         {:ok, step} <- Records.optional_text(attrs[:step_id], 255),
         {:ok, role} <- role(attrs[:role], owner),
         {:ok, ordinal} <- optional_count(attrs[:ordinal]),
         {:ok, call} <- Records.optional_text(attrs[:tool_call_id], 255),
         true <-
           (is_nil(owner) and is_nil(turn)) or
             (not is_nil(owner) and not is_nil(turn) and not is_nil(step)),
         {:ok, digest} <- Codec.digest(description, :operation) do
      {:ok,
       %{
         id: id,
         description: description,
         description_digest: digest,
         sources: sources,
         owner_agent_id: owner,
         turn_id: turn,
         step_id: step,
         role: role,
         ordinal: ordinal,
         tool_call_id: call
       }}
    else
      false -> {:error, :invalid_data}
      error -> error
    end
  end

  defp role(nil, nil), do: {:ok, nil}
  defp role(value, _), do: Records.enum(value, ~w(model tool summary))
  defp optional_count(nil), do: {:ok, nil}
  defp optional_count(value), do: Records.count(value)

  defp description(value) when is_map(value) and not is_struct(value) do
    valid =
      Enum.all?(Map.keys(value), &(&1 in @description_keys)) and
        is_map(value["payload"]) and value["protocol_version"] == 1

    with true <- valid,
         {:ok, _} <- Records.text(value["kind"], 255),
         {:ok, value} <- Records.json(value, :operation) do
      {:ok, value}
    else
      false -> {:error, :invalid_data}
      error -> error
    end
  end

  defp description(_), do: {:error, :invalid_data}

  @doc false
  def validate_attempt(attrs) do
    with {:ok, _} <-
           Records.fields(attrs, [:attempt_id, :executor_id, :executor_boot_id, :budget], []),
         {:ok, _} <- Records.uuid(attrs.attempt_id),
         {:ok, _} <- Records.uuid(attrs.executor_id),
         {:ok, _} <- Records.uuid(attrs.executor_boot_id),
         {:ok, _} <- Records.json(attrs.budget, :event),
         do: {:ok, attrs}
  end

  @doc "Internal transaction participant; caller must validate ownership and sources."
  def insert_prepared(repo, operation, attempt) do
    attrs =
      Map.merge(operation, %{
        lock_version: 0,
        history_seq: 1,
        schema_version: 1,
        recorded_at: DateTime.utc_now()
      })

    execution =
      Map.merge(attempt, %{
        operation_id: operation.id,
        description_digest: operation.description_digest,
        dispatch_state: "prepared",
        lock_version: 0,
        recorded_at: DateTime.utc_now()
      })

    with :ok <- References.verify(repo, operation.description),
         {:ok, _} <- Records.insert(repo, Operation.changeset(%Operation{}, attrs)),
         {:ok, _} <- Records.insert(repo, Execution.changeset(%Execution{}, execution)),
         {:ok, _} <-
           insert_event(repo, operation.id, 1, "operation.prepared", %{
             "description_digest" => operation.description_digest
           }) do
      {:ok, prepared_response(operation, attempt)}
    end
  end

  defp prepared_response(operation, attempt) do
    %{
      "operation_id" => operation.id,
      "description_digest" => operation.description_digest,
      "attempt_id" => attempt.attempt_id,
      "attempt_version" => 0,
      "lock_version" => 0,
      "dispatch_state" => "prepared"
    }
  end

  def claim_dispatch(repo, attrs) do
    with {:ok, _} <- Records.fields(attrs, [:operation_id, :attempt_id, :expected_version], []),
         {:ok, _} <- Records.uuid(attrs.operation_id),
         {:ok, _} <- Records.uuid(attrs.attempt_id),
         {:ok, _} <- Records.count(attrs.expected_version) do
      Records.transact(repo, fn -> claim(repo, attrs) end)
    end
  end

  defp claim(repo, attrs) do
    with {:ok, execution} <- Records.get(repo, Execution, attrs.attempt_id),
         true <- execution.operation_id == attrs.operation_id,
         :ok <- claim_generation(repo, execution.operation_id) do
      eligible = from(o in Operation, where: is_nil(o.accepted_result), select: o.id)

      query =
        from(e in Execution,
          where:
            e.attempt_id == ^attrs.attempt_id and e.operation_id in subquery(eligible) and
              e.dispatch_state == "prepared" and e.lock_version == ^attrs.expected_version
        )

      case repo.update_all(
             query,
             [set: [dispatch_state: "send_claimed", lock_version: attrs.expected_version + 1]],
             log: false
           ) do
        {1, _} ->
          {:ok,
           Records.plain(%{
             execution
             | dispatch_state: "send_claimed",
               lock_version: attrs.expected_version + 1
           })}

        _ ->
          {:error, :conflict}
      end
    else
      false -> {:error, :conflict}
      error -> error
    end
  end

  defp claim_generation(repo, id) do
    with {:ok, op} <- claim_record(repo, Operation, id, "FOR UPDATE") do
      owner_generation(repo, op)
    end
  end

  defp owner_generation(_repo, %Operation{owner_agent_id: nil}), do: :ok

  defp owner_generation(repo, op) do
    with {:ok, agent} <- claim_record(repo, Agent, op.owner_agent_id, "FOR SHARE") do
      if agent.generation == op.owner_generation, do: :ok, else: {:error, :stale_generation}
    end
  end

  # SQLite's immediate transaction already serializes writers. PostgreSQL must
  # hold the checked facts until claim commit, against acceptance and restore.
  defp claim_record(repo, schema, id, lock) do
    query = from(row in schema, where: row.id == ^id)

    query =
      if repo.__adapter__() == Ecto.Adapters.Postgres, do: claim_lock(query, lock), else: query

    case repo.one(query, log: false) do
      nil -> {:error, :conflict}
      record -> {:ok, record}
    end
  end

  defp claim_lock(query, "FOR UPDATE"), do: Ecto.Query.lock(query, "FOR UPDATE")
  defp claim_lock(query, "FOR SHARE"), do: Ecto.Query.lock(query, "FOR SHARE")

  def record_evidence(repo, attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [:id, :operation_id, :attempt_id, :executor_id, :evidence_id, :content],
             [:resolution]
           ),
         :ok <- identities(attrs, [:id, :operation_id, :attempt_id, :executor_id, :evidence_id]),
         {:ok, _} <- Records.json(attrs.content, :event),
         {:ok, _} <- Records.json(attrs[:resolution], :event),
         {:ok, digest} <- Codec.digest(attrs.content, :event) do
      Records.transact(repo, fn -> evidence(repo, Map.put(attrs, :digest, digest)) end)
    end
  end

  defp evidence(repo, attrs) do
    with {:ok, execution} <- Records.get(repo, Execution, attrs.attempt_id),
         true <-
           execution.operation_id == attrs.operation_id and
             execution.executor_id == attrs.executor_id do
      query =
        from(e in ExecutionEvidence,
          where: e.executor_id == ^attrs.executor_id and e.evidence_id == ^attrs.evidence_id
        )

      case repo.one(query, log: false) do
        nil ->
          insert_evidence(repo, attrs)

        stored ->
          replay_evidence(stored, attrs)
      end
    else
      false -> {:error, :conflict}
      error -> error
    end
  end

  defp replay_evidence(stored, attrs) do
    if stored.digest == attrs.digest and stored.operation_id == attrs.operation_id and
         stored.attempt_id == attrs.attempt_id and stored.resolution == attrs[:resolution],
       do: {:ok, Records.plain(stored)},
       else: {:error, :conflict}
  end

  defp insert_evidence(repo, attrs) do
    changeset =
      ExecutionEvidence.changeset(
        %ExecutionEvidence{},
        Map.put(attrs, :recorded_at, DateTime.utc_now())
      )

    with {:ok, stored} <- Records.insert(repo, changeset), do: {:ok, Records.plain(stored)}
  end

  def accept_result(repo, attrs) do
    with {:ok, _} <-
           Records.fields(attrs, [:operation_id, :expected_version, :result], [
             :evidence_id,
             :artifact_ids
           ]),
         {:ok, _} <- Records.uuid(attrs.operation_id),
         {:ok, _} <- Records.count(attrs.expected_version),
         {:ok, _} <- Records.optional_uuid(attrs[:evidence_id]),
         {:ok, _} <- Records.json(attrs.result, :result),
         {:ok, _} <- Codec.digest(attrs.result, :result) do
      Records.transact(repo, fn -> accept(repo, attrs) end)
    end
  end

  defp accept(repo, attrs) do
    with {:ok, operation} <- Records.get(repo, Operation, attrs.operation_id),
         :ok <- evidence_reference(repo, operation.id, attrs[:evidence_id]),
         :ok <- References.verify(repo, attrs.result),
         :ok <- Artifacts.verify_references(repo, attrs[:artifact_ids] || []) do
      if is_nil(operation.accepted_result),
        do: accept_new(repo, operation, attrs),
        else: replay_accept(operation, attrs)
    end
  end

  defp evidence_reference(_repo, _id, nil), do: :ok

  defp evidence_reference(repo, id, evidence_id) do
    case repo.get(ExecutionEvidence, evidence_id, log: false) do
      %ExecutionEvidence{operation_id: ^id} -> :ok
      _ -> {:error, :conflict}
    end
  end

  defp accept_new(repo, operation, attrs) do
    query =
      from(o in Operation,
        where:
          o.id == ^operation.id and is_nil(o.accepted_result) and
            o.lock_version == ^attrs.expected_version
      )

    seq = operation.history_seq + 1

    updates = [
      accepted_result: attrs.result,
      accepted_evidence_id: attrs[:evidence_id],
      lock_version: attrs.expected_version + 1,
      history_seq: seq
    ]

    case repo.update_all(query, [set: updates], log: false) do
      {1, _} ->
        {:ok, digest} = Codec.digest(attrs.result, :result)

        with {:ok, _} <-
               insert_event(repo, operation.id, seq, "operation.result_accepted", %{
                 "accepted_digest" => digest
               }) do
          {:ok,
           accepted_response(%{
             operation
             | accepted_result: attrs.result,
               accepted_evidence_id: attrs[:evidence_id],
               history_seq: seq,
               lock_version: attrs.expected_version + 1
           })}
        end

      _ ->
        {:error, :conflict}
    end
  end

  defp replay_accept(operation, attrs) do
    if operation.accepted_result == attrs.result and
         operation.accepted_evidence_id == attrs[:evidence_id],
       do: {:ok, accepted_response(operation)},
       else: {:error, :conflict}
  end

  defp accepted_response(operation) do
    {:ok, digest} = Codec.digest(operation.accepted_result, :result)

    %{
      "operation_id" => operation.id,
      "accepted_result" => operation.accepted_result,
      "accepted_digest" => digest,
      "accepted_evidence_id" => operation.accepted_evidence_id,
      "lock_version" => operation.lock_version,
      "history_seq" => operation.history_seq
    }
  end

  def fetch(repo, id) do
    with {:ok, id} <- Records.uuid(id) do
      Transaction.read(fn -> read_operation(repo, id) end)
    end
  end

  defp read_operation(repo, id) do
    with {:ok, operation} <- Records.get(repo, Operation, id) do
      attempt = repo.one(from(e in Execution, where: e.operation_id == ^id), log: false)
      {:ok, %{"operation" => Records.plain(operation), "attempt" => Records.plain(attempt)}}
    end
  end

  defp identities(attrs, keys) do
    if Enum.all?(keys, &Codec.uuid?(Map.get(attrs, &1))), do: :ok, else: {:error, :invalid_data}
  end

  defp insert_event(repo, id, seq, type, payload) do
    Records.insert(
      repo,
      Records.event_changeset(%{
        id: Ecto.UUID.generate(),
        scope_id: id,
        operation_id: id,
        seq: seq,
        type: type,
        schema_version: 1,
        payload: payload,
        recorded_at: DateTime.utc_now()
      })
    )
  end
end
