defmodule Beamlet.Runtime.Persistence do
  @moduledoc """
  Explicit opt-in durable wiring for the normal Runtime path.

  Supplying this struct to `Beamlet.Runtime.start_link/1`/`submit/2` makes the
  authority commit an Operation with one prepared attempt before dispatch, the
  executor journal its own start intent before starting a worker, and the
  coordinator accept exactly one authority Result before notifying a sink.
  Without it Runtime stays ephemeral. The struct carries only opaque Repo handles
  and stable identities; PIDs, references, monitors, timers and worker handles
  stay in memory.

  An `owner` names the Agent/turn an accepted Result belongs to and carries
  exactly one Agent position: `expected_version` for the strict version CAS of a
  single owned Operation, or `accept_seq` for the position a whole batch reserved
  for that Operation's Result (siblings of one batch accept concurrently).
  """
  alias Beamlet.Actions.{Operation, Result}
  alias Beamlet.Storage.Codec

  @enforce_keys [:authority_repo, :journal_repo, :authority_id, :executor_id, :executor_boot_id]
  defstruct [
    :authority_repo,
    :journal_repo,
    :authority_id,
    :executor_id,
    :executor_boot_id,
    :owner
  ]

  @type owner :: %{
          agent_id: binary(),
          turn_id: binary(),
          expected_version: non_neg_integer() | nil,
          expected_generation: non_neg_integer(),
          accept_seq: non_neg_integer() | nil
        }
  @type t :: %__MODULE__{
          authority_repo: term(),
          journal_repo: term(),
          authority_id: binary(),
          executor_id: binary(),
          executor_boot_id: binary(),
          owner: owner() | nil
        }

  def new(nil), do: nil
  def new(%__MODULE__{} = persistence), do: validate!(persistence)

  def new(opts) when is_list(opts) do
    validate!(%__MODULE__{
      authority_repo: opts[:authority_repo],
      journal_repo: opts[:journal_repo],
      authority_id: opts[:authority_id],
      executor_id: opts[:executor_id],
      executor_boot_id: opts[:executor_boot_id],
      owner: opts[:owner]
    })
  end

  def uuid, do: Ecto.UUID.generate()

  @doc "Persistent, non executable Operation description; credentials and placement stay local."
  def description(%Operation{} = operation) do
    %{
      "kind" => operation.kind,
      "protocol_version" => operation.version,
      "payload" => operation.payload,
      "budget" => %{"budget_ms" => operation.budget_ms},
      "claims" => operation.claims
    }
  end

  @doc "Authority commit of the immutable Operation and one prepared attempt, before dispatch."
  def prepare(nil, _operation), do: {:ok, nil}

  def prepare(%__MODULE__{} = persistence, %Operation{} = operation) do
    attempt_id = uuid()

    attrs = %{
      operation:
        persistence.owner
        |> owner_fields()
        |> Map.merge(%{id: uuid(), description: description(operation)}),
      attempt: %{
        attempt_id: attempt_id,
        executor_id: persistence.executor_id,
        executor_boot_id: persistence.executor_boot_id,
        budget: %{"budget_ms" => operation.budget_ms}
      },
      event: %{id: uuid(), type: "operation.prepared", payload: %{"attempt_id" => attempt_id}}
    }

    attrs =
      case persistence.owner do
        nil ->
          attrs

        owner ->
          Map.put(attrs, :agent, %{
            expected_version: owner.expected_version,
            expected_generation: owner.expected_generation
          })
      end

    case Beamlet.Storage.OperationRecords.prepare(persistence.authority_repo, attrs) do
      {:ok, prepared} -> {:ok, prepared}
      {:error, reason} -> {:error, submit_error(reason)}
    end
  end

  @doc "Executor-local evidence: terminal observation plus stable receipt identity."
  def receipt(journal, %Result{} = result, termination) do
    content = %{
      "version" => 1,
      "authority_id" => journal.authority_id,
      "operation_id" => journal.operation_id,
      "attempt_id" => journal.attempt_id,
      "executor_id" => journal.executor_id,
      "executor_boot_id" => journal.executor_boot_id,
      "description_digest" => journal.description_digest,
      "result" => result_payload(result),
      "termination" => termination
    }

    case Codec.digest(content, :event) do
      {:ok, digest} -> {:ok, %{id: journal.receipt_id, digest: digest, content: content}}
      {:error, _} -> {:error, :durable_unavailable}
    end
  end

  @doc "Plain receipt evidence for the authority; no structs or live values are persisted."
  def evidence(receipt) do
    %{
      "version" => 1,
      "receipt_id" => receipt.id,
      "receipt_digest" => receipt.digest,
      "result" => receipt.content["result"],
      "termination" => receipt.content["termination"]
    }
  end

  def result_payload(%Result{} = result) do
    %{
      "operation_id" => result.operation_id,
      "execution_id" => result.execution_id,
      "status" => Atom.to_string(result.status),
      "reason" => value(result.reason),
      "value" => value(result.value),
      "source" => Atom.to_string(result.source),
      "metadata" => Map.new(result.metadata, fn {key, item} -> {to_string(key), value(item)} end)
    }
  end

  @doc false
  # A durable Result is plain JSON data: labels the handler carried as atoms are
  # stored as strings, so a receipt always has a stable digest.
  def value(nil), do: nil
  def value(item) when is_atom(item), do: Atom.to_string(item)
  def value(item) when is_list(item), do: Enum.map(item, &value/1)

  def value(item) when is_map(item) and not is_struct(item) do
    Map.new(item, fn {key, child} -> {value(key), value(child)} end)
  end

  def value(item), do: item

  defp owner_fields(nil), do: %{}

  defp owner_fields(owner) do
    %{owner_agent_id: owner.agent_id, turn_id: owner.turn_id}
  end

  defp submit_error(:invalid_data), do: :invalid_operation
  defp submit_error(:limit), do: :invalid_operation
  defp submit_error(_reason), do: :unavailable

  defp validate!(%__MODULE__{} = persistence) do
    valid =
      not is_nil(persistence.authority_repo) and not is_nil(persistence.journal_repo) and
        Codec.uuid?(persistence.authority_id) and Codec.uuid?(persistence.executor_id) and
        Codec.uuid?(persistence.executor_boot_id) and owner?(persistence.owner)

    unless valid, do: raise(ArgumentError, "invalid persistence configuration")
    persistence
  end

  defp owner?(nil), do: true

  defp owner?(owner) do
    is_map(owner) and not is_struct(owner) and
      Map.keys(owner) --
        [:agent_id, :turn_id, :expected_version, :expected_generation, :accept_seq] == [] and
      Codec.uuid?(owner[:agent_id]) and Codec.uuid?(owner[:turn_id]) and
      position?(owner[:expected_version], owner[:accept_seq]) and
      is_integer(owner[:expected_generation]) and owner[:expected_generation] >= 0
  end

  defp position?(version, accept_seq) do
    (is_integer(version) and version >= 0 and is_nil(accept_seq)) or
      (is_nil(version) and is_integer(accept_seq) and accept_seq > 0)
  end
end
