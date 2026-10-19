defmodule Beamlet.Agent.Storage.RecordChangeset do
  @moduledoc false
  @spec build(struct(), term(), [atom()]) :: Ecto.Changeset.t()
  @spec homogeneous?([atom() | String.t()]) :: boolean()
  @spec invalid(struct()) :: Ecto.Changeset.t()
  @spec validate_fields(Ecto.Changeset.t(), [atom()]) :: Ecto.Changeset.t()
  @spec validate_field(Ecto.Changeset.t(), atom(), term()) :: Ecto.Changeset.t()
  @spec validate_json(Ecto.Changeset.t(), atom(), term(), atom()) :: Ecto.Changeset.t()
  @spec validate_string(Ecto.Changeset.t(), atom(), term()) :: Ecto.Changeset.t()
  import Ecto.Changeset
  alias Beamlet.Agent.Storage.Codec
  alias Beamlet.Agent.Storage.JSON

  @uuid_fields ~w(id authority_id agent_id head_checkpoint_id forked_from_agent_id forked_from_checkpoint_id turn_id scope_id dispatch_scope_id operation_id causation_id source_agent_id source_event_id owner_agent_id accepted_evidence_id attempt_id executor_id executor_boot_id evidence_id command_id receipt_id)a
  @continuations ~w(await_input model_prepared tool_batch_prepared await_model_result await_tool_results reply_recorded results_to_consume ready_for_next_step await_delegation await_peer interrupted blocked completed)

  def build(record, attrs, required) when is_map(attrs) and not is_struct(attrs) do
    fields = record.__struct__.__schema__(:fields)
    allowed = Enum.map(fields, &Atom.to_string/1)
    known? = Enum.all?(Map.keys(attrs), &((is_atom(&1) and &1 in fields) or &1 in allowed))

    if known? and homogeneous?(Map.keys(attrs)) do
      record
      |> cast(attrs, fields, empty_values: [])
      |> validate_required(required)
      |> validate_fields(fields)
    else
      invalid(record)
    end
  end

  def build(record, _, _), do: invalid(record)
  defp homogeneous?([]), do: true
  defp homogeneous?([key | keys]), do: Enum.all?(keys, &(is_atom(&1) == is_atom(key)))
  defp invalid(record), do: record |> change() |> add_error(:base, "invalid_data")

  defp validate_fields(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      validate_field(acc, field, get_field(acc, field))
    end)
  end

  defp validate_field(cs, _, nil), do: cs

  defp validate_field(cs, field, value) when field in @uuid_fields do
    if Codec.uuid?(value), do: cs, else: add_error(cs, field, "invalid_data")
  end

  defp validate_field(cs, field, _)
       when field in [
              :generation,
              :lock_version,
              :history_seq,
              :ordinal,
              :size,
              :through_seq,
              :owner_generation,
              :prepared_seq
            ],
       do: validate_number(cs, field, greater_than_or_equal_to: 0)

  defp validate_field(cs, :reducer_version, _),
    do: validate_number(cs, :reducer_version, greater_than: 0)

  defp validate_field(cs, :schema_version, _), do: validate_inclusion(cs, :schema_version, [1])
  defp validate_field(cs, :seq, _), do: validate_number(cs, :seq, greater_than: 0)

  defp validate_field(cs, :dispatch_state, _),
    do: validate_inclusion(cs, :dispatch_state, ~w(prepared send_claimed))

  defp validate_field(cs, :state, _),
    do: validate_inclusion(cs, :state, ~w(start_intent terminal unknown_after_restart))

  defp validate_field(cs, :stop_reason, _),
    do: validate_inclusion(cs, :stop_reason, ~w(deadline cancelled))

  defp validate_field(cs, :continuation, _),
    do: validate_inclusion(cs, :continuation, @continuations)

  defp validate_field(cs, field, _)
       when field in [:digest, :description_digest, :request_digest, :receipt_digest],
       do: validate_format(cs, field, ~r/\A[0-9a-f]{64}\z/)

  defp validate_field(cs, field, value) do
    case JSON.kind(cs.data.__struct__.__schema__(:type, field)) do
      nil -> validate_string(cs, field, value)
      kind -> validate_json(cs, field, value, kind)
    end
  end

  defp validate_json(cs, field, value, kind) do
    case Codec.encode(value, kind) do
      {:ok, _} -> cs
      {:error, reason} -> add_error(cs, field, Atom.to_string(reason))
    end
  end

  defp validate_string(cs, field, value) when is_binary(value) and field != :content do
    if String.valid?(value) and byte_size(value) <= 255,
      do: cs,
      else: add_error(cs, field, "invalid_data")
  end

  defp validate_string(cs, _, _), do: cs
end
