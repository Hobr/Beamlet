defmodule Beamlet.Agent.Storage.OperationRecords do
  @moduledoc "Agent-owned operation projections and association validation."
  alias Beamlet.Agent.Storage.Records
  alias Beamlet.Agent.Storage.Schema.Operation

  @typedoc "Validated association input. Unowned intermediate operations may have nil owner/turn/step/role."
  @type operation :: %{
          id: String.t(),
          description: Records.object(),
          description_digest: String.t(),
          sources: [Records.value()],
          owner_agent_id: String.t() | nil,
          turn_id: String.t() | nil,
          step_id: String.t() | nil,
          role: String.t() | nil,
          ordinal: non_neg_integer() | nil,
          tool_call_id: String.t() | nil
        }
  @type attempt :: Beamlet.Actions.Storage.OperationRecords.attempt()
  @spec validate_operation(term()) :: Records.result(operation())
  @spec role(term(), String.t() | nil) :: Records.result(String.t() | nil)
  @spec optional_count(term()) :: Records.result(non_neg_integer() | nil)
  @spec description(term()) :: Records.result(Records.object())
  @spec validate_attempt(term()) :: Records.result(attempt())
  @spec fetch(module(), term()) :: Records.result(Records.object())
  @spec read_operation(module(), String.t()) :: Records.result(Records.object())
  alias Beamlet.Agent.Storage.Codec
  import Ecto.Query
  alias Beamlet.Actions.Storage.Schema.Execution
  alias Beamlet.Agent.Storage.Read
  @description_keys ~w(kind protocol_version payload refs budget claims safety)
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

  def fetch(repo, id) do
    with {:ok, _} <- Records.uuid(id), do: Read.read(fn -> read_operation(repo, id) end)
  end

  defp read_operation(repo, id) do
    with {:ok, op} <- Records.get(repo, Operation, id) do
      attempt = repo.one(from(e in Execution, where: e.operation_id == ^id), log: false)
      {:ok, %{"operation" => Records.plain(op), "attempt" => Records.plain(attempt)}}
    end
  end
end
