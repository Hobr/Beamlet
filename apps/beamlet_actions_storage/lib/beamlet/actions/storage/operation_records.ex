defmodule Beamlet.Actions.Storage.OperationRecords do
  @moduledoc "Immutable requests, single dispatch claims, evidence and Operation-scoped acceptance."
  import Ecto.Query
  alias Beamlet.Actions.Storage.Codec
  alias Beamlet.Actions.Storage.DispatchScopes
  alias Beamlet.Actions.Storage.Read
  alias Beamlet.Actions.Storage.Records
  alias Beamlet.Actions.Storage.Schema.Execution
  alias Beamlet.Actions.Storage.Schema.ExecutionEvidence
  alias Beamlet.Actions.Storage.Schema.Operation
  alias Beamlet.Actions.Storage.Schema.OperationEvent
  alias Beamlet.Storage.Artifacts
  alias Beamlet.Storage.References
  alias Beamlet.Storage.Transaction

  @typedoc "Validated immutable request, including the optional paired scope binding."
  @type operation :: %{
          id: String.t(),
          description: Records.object(),
          description_digest: String.t(),
          dispatch_scope_id: String.t() | nil,
          dispatch_epoch: non_neg_integer() | nil
        }
  @type attempt :: %{
          attempt_id: String.t(),
          executor_id: String.t(),
          executor_boot_id: String.t(),
          budget: Records.value()
        }
  @typep evidence_input :: %{
           optional(:resolution) => Records.value(),
           id: String.t(),
           operation_id: String.t(),
           attempt_id: String.t(),
           executor_id: String.t(),
           evidence_id: String.t(),
           content: Records.value(),
           digest: String.t()
         }
  @typep acceptance :: %{
           optional(:evidence_id) => String.t() | nil,
           optional(:artifact_ids) => [String.t()] | nil,
           operation_id: String.t(),
           expected_version: non_neg_integer(),
           result: Records.value()
         }

  @spec prepare(module(), term()) :: Records.result(Records.object())
  @spec prepare_in_transaction(module(), term()) :: Records.result(Records.object())
  @spec prepare_independent(module(), operation(), attempt()) :: Records.result(Records.object())
  @spec validate_operation(term()) :: Records.result(operation())
  @spec description(term()) :: Records.result(Records.object())
  @spec validate_attempt(term()) :: Records.result(attempt())
  @spec insert_prepared(module(), operation(), attempt()) :: Records.result(Records.object())
  @spec prepared_response(operation(), attempt()) :: Records.object()
  @spec claim_dispatch(module(), term()) :: Records.result(Records.object())
  @spec claim(module(), %{
          optional(:expected_operation) => term(),
          operation_id: String.t(),
          attempt_id: String.t(),
          expected_version: non_neg_integer()
        }) :: Records.result(Records.object())
  @spec claim_scope(module(), String.t(), term()) :: :ok | {:error, Records.error()}
  @spec expected_operation(Operation.t(), term()) :: :ok | {:error, Records.error()}
  @spec claim_record(module(), module(), String.t(), String.t()) ::
          {:ok, struct()} | {:error, :conflict}
  @spec claim_lock(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  @spec record_evidence(module(), term()) :: Records.result(Records.object())
  @spec evidence(module(), evidence_input()) :: Records.result(Records.object())
  @spec replay_evidence(ExecutionEvidence.t(), evidence_input()) ::
          Records.result(Records.object())
  @spec insert_evidence(module(), evidence_input()) :: Records.result(Records.object())
  @spec accept_result(module(), term()) :: Records.result(Records.object())
  @spec accept(module(), acceptance()) :: Records.result(Records.object())
  @spec evidence_reference(module(), String.t(), String.t() | nil) :: :ok | {:error, :conflict}
  @spec accept_new(module(), Operation.t(), acceptance()) :: Records.result(Records.object())
  @spec replay_accept(Operation.t(), acceptance()) :: Records.result(Records.object())
  @spec accepted_response(Operation.t()) :: Records.object()
  @spec fetch(module(), term()) :: Records.result(Records.object())
  @spec read_operation(module(), String.t()) :: Records.result(Records.object())
  @spec identities(map(), [atom()]) :: :ok | {:error, :invalid_data}
  @spec insert_event(module(), String.t(), pos_integer(), String.t(), Records.object()) ::
          Records.result(OperationEvent.t())

  @description_keys ~w(kind protocol_version payload refs budget claims safety)

  def prepare(repo, attrs),
    do: Records.transact(repo, fn -> prepare_in_transaction(repo, attrs) end)

  def prepare_in_transaction(repo, attrs) do
    Transaction.participate(repo, fn ->
      with {:ok, _} <- Records.fields(attrs, [:operation, :attempt], []),
           {:ok, operation} <- validate_operation(attrs.operation),
           {:ok, attempt} <- validate_attempt(attrs.attempt),
           :ok <-
             DispatchScopes.check(repo, operation.dispatch_scope_id, operation.dispatch_epoch) do
        prepare_independent(repo, operation, attempt)
      end
    end)
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
           Records.fields(attrs, [:id, :description], [:dispatch_scope_id, :dispatch_epoch]),
         {:ok, id} <- Records.uuid(attrs.id),
         {:ok, description} <- description(attrs.description),
         :ok <- DispatchScopes.validate_binding(attrs[:dispatch_scope_id], attrs[:dispatch_epoch]),
         {:ok, digest} <- Codec.digest(description, :operation) do
      {:ok,
       %{
         id: id,
         description: description,
         description_digest: digest,
         dispatch_scope_id: attrs[:dispatch_scope_id],
         dispatch_epoch: attrs[:dispatch_epoch]
       }}
    end
  end

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

  defp insert_prepared(repo, operation, attempt) do
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
      "dispatch_state" => "prepared",
      "dispatch_scope_id" => operation.dispatch_scope_id,
      "dispatch_epoch" => operation.dispatch_epoch
    }
  end

  def claim_dispatch(repo, attrs) do
    with {:ok, _} <-
           Records.fields(attrs, [:operation_id, :attempt_id, :expected_version], [
             :expected_operation
           ]),
         {:ok, _} <- Records.uuid(attrs.operation_id),
         {:ok, _} <- Records.uuid(attrs.attempt_id),
         {:ok, _} <- Records.count(attrs.expected_version) do
      Records.transact(repo, fn -> claim(repo, attrs) end)
    end
  end

  defp claim(repo, attrs) do
    with {:ok, execution} <- Records.get(repo, Execution, attrs.attempt_id),
         true <- execution.operation_id == attrs.operation_id,
         :ok <- claim_scope(repo, execution.operation_id, attrs[:expected_operation]) do
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

  defp claim_scope(repo, id, expected) do
    with {:ok, op} <- Records.get(repo, Operation, id),
         :ok <- DispatchScopes.check(repo, op.dispatch_scope_id, op.dispatch_epoch),
         {:ok, locked} <- claim_record(repo, Operation, id, "FOR UPDATE") do
      expected_operation(locked, expected)
    end
  end

  defp expected_operation(_operation, nil), do: :ok

  defp expected_operation(operation, expected) do
    with {:ok, _} <-
           Records.fields(
             expected,
             [:description_digest, :lock_version, :dispatch_scope_id, :dispatch_epoch],
             []
           ),
         {:ok, _} <- Records.digest(expected.description_digest),
         {:ok, _} <- Records.count(expected.lock_version),
         :ok <-
           DispatchScopes.validate_binding(expected.dispatch_scope_id, expected.dispatch_epoch) do
      if Map.take(operation, Map.keys(expected)) == expected, do: :ok, else: {:error, :conflict}
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
      Read.read(fn -> read_operation(repo, id) end)
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
      OperationEvent.changeset(%OperationEvent{}, %{
        id: Ecto.UUID.generate(),
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
