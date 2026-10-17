defmodule Beamlet.Storage.ExecutorJournal do
  @moduledoc """
  Executor-local SQLite evidence journal. `claim_start/2` is insert-once on
  `(authority_id, attempt_id)` and only reports the stored state, so a duplicate
  admission never starts a second worker. The first recorded stop cause survives
  competing triggers; a terminal result, its attachments and the receipt commit
  together. `unknown_after_restart` is never rewritten into a claim that work did
  not happen: only an explicit terminal report from an active start intent can
  produce a terminal fact.
  """
  import Ecto.Query
  alias Beamlet.Storage.{Codec, Records, TerminalArtifacts, Transaction}
  alias Beamlet.Storage.Schema.JournalAttempt

  @stop_reasons ~w(deadline cancelled)
  @transaction_budget 33_554_432

  def claim_start(repo, attrs) do
    with {:ok, input} <- validate_start(attrs) do
      Records.transact(repo, fn -> write_start(repo, input) end)
    end
  end

  def record_stop(repo, attrs) do
    with {:ok, input} <- validate_stop(attrs) do
      Records.transact(repo, fn -> write_stop(repo, input) end)
    end
  end

  def record_terminal(repo, attrs) do
    with {:ok, input} <- validate_terminal(attrs) do
      Records.transact(repo, fn -> write_terminal(repo, input) end)
    end
  end

  def acknowledge(repo, attrs) do
    with {:ok, input} <- validate_acknowledge(attrs) do
      Records.transact(repo, fn -> write_acknowledge(repo, input) end)
    end
  end

  @doc """
  Marks start intents left by another boot as `unknown_after_restart`. This is the
  only way to reach that state; the journal never infers "not executed".
  """
  def mark_unknown_after_restart(repo, attrs) do
    with {:ok, input} <- validate_restart(attrs) do
      Records.transact(repo, fn -> write_restart(repo, input) end)
    end
  end

  def fetch(repo, authority_id, attempt_id) do
    with {:ok, authority_id} <- Records.uuid(authority_id),
         {:ok, attempt_id} <- Records.uuid(attempt_id) do
      Transaction.read(fn ->
        case record(repo, authority_id, attempt_id) do
          nil -> {:error, :conflict}
          stored -> {:ok, Records.plain(stored)}
        end
      end)
    end
  end

  ## Claim

  defp validate_start(attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [
               :id,
               :authority_id,
               :operation_id,
               :attempt_id,
               :description_digest,
               :executor_id,
               :executor_boot_id
             ],
             []
           ),
         {:ok, id} <- Records.uuid(attrs[:id]),
         {:ok, authority_id} <- Records.uuid(attrs[:authority_id]),
         {:ok, operation_id} <- Records.uuid(attrs[:operation_id]),
         {:ok, attempt_id} <- Records.uuid(attrs[:attempt_id]),
         {:ok, digest} <- Records.digest(attrs[:description_digest]),
         {:ok, executor_id} <- Records.uuid(attrs[:executor_id]),
         {:ok, boot_id} <- Records.uuid(attrs[:executor_boot_id]) do
      {:ok,
       %{
         id: id,
         authority_id: authority_id,
         operation_id: operation_id,
         attempt_id: attempt_id,
         description_digest: digest,
         executor_id: executor_id,
         executor_boot_id: boot_id
       }}
    end
  end

  defp write_start(repo, input) do
    case record(repo, input.authority_id, input.attempt_id) do
      nil ->
        Records.insert(
          repo,
          JournalAttempt.changeset(%JournalAttempt{}, %{
            id: input.id,
            authority_id: input.authority_id,
            operation_id: input.operation_id,
            attempt_id: input.attempt_id,
            description_digest: input.description_digest,
            executor_id: input.executor_id,
            executor_boot_id: input.executor_boot_id,
            state: "start_intent",
            acknowledged: false,
            schema_version: 1,
            lock_version: 0,
            recorded_at: DateTime.utc_now()
          })
          |> Ecto.Changeset.unique_constraint([:authority_id, :attempt_id],
            name: :journal_attempts_authority_id_attempt_id_index
          )
        )
        |> case do
          {:ok, stored} -> {:ok, start_response(stored)}
          error -> error
        end

      stored ->
        if same_identity?(stored, input),
          do: {:ok, start_response(stored)},
          else: {:error, :conflict}
    end
  end

  defp same_identity?(stored, input) do
    stored.operation_id == input.operation_id and
      stored.description_digest == input.description_digest and
      stored.executor_id == input.executor_id and
      stored.executor_boot_id == input.executor_boot_id
  end

  defp start_response(stored) do
    %{
      "record_id" => stored.id,
      "authority_id" => stored.authority_id,
      "operation_id" => stored.operation_id,
      "attempt_id" => stored.attempt_id,
      "state" => stored.state,
      "stop_reason" => stored.stop_reason,
      "acknowledged" => stored.acknowledged,
      "receipt_id" => stored.receipt_id,
      "lock_version" => stored.lock_version
    }
  end

  ## Stop cause

  defp validate_stop(attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [:authority_id, :attempt_id, :stop_reason, :expected_version],
             []
           ),
         {:ok, authority_id} <- Records.uuid(attrs[:authority_id]),
         {:ok, attempt_id} <- Records.uuid(attrs[:attempt_id]),
         {:ok, reason} <- Records.enum(attrs[:stop_reason], @stop_reasons),
         {:ok, version} <- Records.count(attrs[:expected_version]) do
      {:ok,
       %{
         authority_id: authority_id,
         attempt_id: attempt_id,
         stop_reason: reason,
         expected_version: version
       }}
    end
  end

  defp write_stop(repo, input) do
    query =
      from(j in JournalAttempt,
        where:
          j.authority_id == ^input.authority_id and j.attempt_id == ^input.attempt_id and
            j.state == "start_intent" and is_nil(j.stop_reason) and
            j.lock_version == ^input.expected_version,
        update: [
          set: [stop_reason: ^input.stop_reason, lock_version: ^(input.expected_version + 1)]
        ]
      )

    case repo.update_all(query, [], log: false) do
      {1, _} ->
        stored_response(repo, input.authority_id, input.attempt_id)

      {0, _} ->
        # Competing triggers do not overwrite the first recorded cause, and a
        # request after terminal/unknown is a no-op that reports the stored fact.
        case record(repo, input.authority_id, input.attempt_id) do
          nil ->
            {:error, :conflict}

          %JournalAttempt{stop_reason: nil, state: "start_intent"} ->
            {:error, :conflict}

          stored ->
            {:ok, terminal_response(stored)}
        end
    end
  end

  ## Terminal

  defp validate_terminal(attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [
               :authority_id,
               :attempt_id,
               :expected_version,
               :termination,
               :terminal_result,
               :terminal_artifacts,
               :receipt_id,
               :receipt_digest,
               :receipt
             ],
             []
           ),
         {:ok, authority_id} <- Records.uuid(attrs[:authority_id]),
         {:ok, attempt_id} <- Records.uuid(attrs[:attempt_id]),
         {:ok, version} <- Records.count(attrs[:expected_version]),
         {:ok, termination} <- Records.json(attrs[:termination], :event),
         {:ok, result} <- Records.json(attrs[:terminal_result], :result),
         {:ok, artifacts} <- TerminalArtifacts.encode(attrs[:terminal_artifacts]),
         {:ok, receipt_id} <- Records.uuid(attrs[:receipt_id]),
         {:ok, receipt} <- Records.json(attrs[:receipt], :event),
         {:ok, digest} <- digest_of(receipt, :event),
         :ok <- same_digest(attrs[:receipt_digest], digest),
         :ok <- within_budget(termination, result, artifacts, receipt) do
      {:ok,
       %{
         authority_id: authority_id,
         attempt_id: attempt_id,
         expected_version: version,
         termination: termination,
         terminal_result: result,
         terminal_artifacts: artifacts,
         receipt_id: receipt_id,
         receipt_digest: digest,
         receipt: receipt
       }}
    end
  end

  defp same_digest(nil, _digest), do: {:error, :invalid_data}
  defp same_digest(digest, digest), do: :ok
  defp same_digest(_, _), do: {:error, :invalid_data}

  defp within_budget(termination, result, artifacts, receipt) do
    with {:ok, termination_bytes} <- encoded_size(termination, :event),
         {:ok, result_bytes} <- encoded_size(result, :result),
         {:ok, artifact_bytes} <- TerminalArtifacts.encoded_size(artifacts),
         {:ok, receipt_bytes} <- encoded_size(receipt, :event) do
      if termination_bytes + result_bytes + artifact_bytes + receipt_bytes <= @transaction_budget,
        do: :ok,
        else: {:error, :limit}
    end
  end

  defp encoded_size(value, kind) do
    case Codec.encode(value, kind) do
      {:ok, bytes} -> {:ok, byte_size(bytes)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_terminal(repo, input) do
    query =
      from(j in JournalAttempt,
        where:
          j.authority_id == ^input.authority_id and j.attempt_id == ^input.attempt_id and
            j.state == "start_intent" and j.lock_version == ^input.expected_version,
        update: [
          set: [
            state: "terminal",
            termination: ^input.termination,
            terminal_result: ^input.terminal_result,
            terminal_artifacts: ^input.terminal_artifacts,
            receipt_id: ^input.receipt_id,
            receipt_digest: ^input.receipt_digest,
            receipt: ^input.receipt,
            lock_version: ^(input.expected_version + 1)
          ]
        ]
      )

    case repo.update_all(query, [], log: false) do
      {1, _} ->
        stored_response(repo, input.authority_id, input.attempt_id)

      {0, _} ->
        case record(repo, input.authority_id, input.attempt_id) do
          %JournalAttempt{state: "terminal"} = stored ->
            if same_terminal?(stored, input),
              do: {:ok, terminal_response(stored)},
              else: {:error, :conflict}

          _ ->
            # Missing row, a stale version, or unknown_after_restart: none may be
            # converted into a terminal fact.
            {:error, :conflict}
        end
    end
  end

  defp same_terminal?(stored, input) do
    stored.receipt_id == input.receipt_id and stored.receipt_digest == input.receipt_digest and
      stored.terminal_result == input.terminal_result and
      stored.terminal_artifacts == input.terminal_artifacts and
      stored.termination == input.termination and stored.receipt == input.receipt
  end

  ## Acknowledgement

  defp validate_acknowledge(attrs) do
    with {:ok, _} <- Records.fields(attrs, [:authority_id, :attempt_id, :expected_version], []),
         {:ok, authority_id} <- Records.uuid(attrs[:authority_id]),
         {:ok, attempt_id} <- Records.uuid(attrs[:attempt_id]),
         {:ok, version} <- Records.count(attrs[:expected_version]) do
      {:ok, %{authority_id: authority_id, attempt_id: attempt_id, expected_version: version}}
    end
  end

  defp write_acknowledge(repo, input) do
    query =
      from(j in JournalAttempt,
        where:
          j.authority_id == ^input.authority_id and j.attempt_id == ^input.attempt_id and
            j.state == "terminal" and j.acknowledged == false and
            j.lock_version == ^input.expected_version,
        update: [set: [acknowledged: true, lock_version: ^(input.expected_version + 1)]]
      )

    case repo.update_all(query, [], log: false) do
      {1, _} ->
        stored_response(repo, input.authority_id, input.attempt_id)

      {0, _} ->
        case record(repo, input.authority_id, input.attempt_id) do
          %JournalAttempt{acknowledged: true} = stored ->
            {:ok, terminal_response(stored)}

          _ ->
            {:error, :conflict}
        end
    end
  end

  ## Restart

  # `keep_executor_boot_id` excludes still-live boots of a shared journal. A caller
  # that owns no live worker (for example a gateway boot, where supervision already
  # killed its workers) omits it and every start intent for that executor is marked.
  defp validate_restart(attrs) do
    with {:ok, _} <-
           Records.fields(attrs, [:authority_id, :executor_id], [:keep_executor_boot_id]),
         {:ok, authority_id} <- Records.uuid(attrs[:authority_id]),
         {:ok, executor_id} <- Records.uuid(attrs[:executor_id]),
         {:ok, boot_id} <- Records.optional_uuid(attrs[:keep_executor_boot_id]) do
      {:ok, %{authority_id: authority_id, executor_id: executor_id, keep_boot_id: boot_id}}
    end
  end

  defp write_restart(repo, input) do
    base =
      from(j in JournalAttempt,
        where:
          j.authority_id == ^input.authority_id and j.executor_id == ^input.executor_id and
            j.state == "start_intent",
        update: [
          set: [state: "unknown_after_restart", lock_version: j.lock_version + 1]
        ]
      )

    query =
      if input.keep_boot_id,
        do: from(j in base, where: j.executor_boot_id != ^input.keep_boot_id),
        else: base

    case repo.update_all(query, [], log: false) do
      {count, _} -> {:ok, %{"marked" => count}}
    end
  end

  ## Shared

  defp record(repo, authority_id, attempt_id) do
    from(j in JournalAttempt,
      where: j.authority_id == ^authority_id and j.attempt_id == ^attempt_id
    )
    |> repo.one(log: false)
  end

  defp stored_response(repo, authority_id, attempt_id) do
    case record(repo, authority_id, attempt_id) do
      nil -> {:error, :conflict}
      stored -> {:ok, terminal_response(stored)}
    end
  end

  defp terminal_response(stored) do
    %{
      "record_id" => stored.id,
      "authority_id" => stored.authority_id,
      "attempt_id" => stored.attempt_id,
      "operation_id" => stored.operation_id,
      "state" => stored.state,
      "stop_reason" => stored.stop_reason,
      "acknowledged" => stored.acknowledged,
      "receipt_id" => stored.receipt_id,
      "lock_version" => stored.lock_version
    }
  end

  defp digest_of(value, kind) do
    case Codec.digest(value, kind) do
      {:ok, digest} -> {:ok, digest}
      {:error, reason} -> {:error, reason}
    end
  end
end
