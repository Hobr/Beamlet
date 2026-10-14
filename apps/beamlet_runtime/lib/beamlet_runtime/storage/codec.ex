defmodule BeamletRuntime.Storage.Codec do
  @moduledoc """
  Versioned internal SQL codec for domain snapshots and History, not a wire decoder.

  Explicit tags preserve structs, tuples and atom keys without creating atoms or
  loading arbitrary modules. Logical maps are tagged too, so user keys cannot
  masquerade as metadata. Unknown versions, fields, modules and atoms fail closed.
  Changes to this representation require an explicit reader/migration decision.
  """
  alias Beamlet.{
    Definition,
    Exclusion,
    Execution,
    Identity,
    Intent,
    Lease,
    Outcome,
    Report,
    Token
  }

  alias Beamlet.Reconciliation.{Command, Decision, Policy, Record}
  alias Beamlet.Report.Source

  @modules [
    Command,
    Decision,
    Policy,
    Record,
    Definition,
    Execution,
    Exclusion,
    Identity,
    Intent,
    Lease,
    Outcome,
    Report,
    Source,
    Token
  ]
  @registry Map.new(@modules, &{Atom.to_string(&1), &1})
  @atoms ~w(open closed prepared start_authorized waiting unknown resolved stop_on_failure retry_once
    succeeded failed cancelled pending success failure not_found not_executed worker callback query
    unstarted idempotency intent_created execution_created execution_claimed lease_expired start_authorized
    report_recorded report_conflict outcome_accepted execution_replaced stop_known_failure
    kind execution_id actor at version details handler protocol generation expires_at from to
    report_id source_kind from_execution_id basis reason old_generation
    adopt_success adopt_failure exclude_from_judgment exclude_all_evidence withdraw_disposition
    verified_completion contract_exclusion verified_withdrawal operator rule keep exclude
    committed stale ineligible evidence_reconciled command_rejection_stored
    decision accepted_base accepted_revision policy decision_index item treatment
    knowledge attempts base revision view decision_kind reviewed_revision
    id kinds query_required evidence_required)a
  @fields Enum.flat_map(@modules, &(Map.keys(&1.__struct__()) -- [:__struct__]))
  @names Map.new(Enum.uniq(@atoms ++ @fields), &{Atom.to_string(&1), &1})

  def encode(value), do: Jason.encode!(%{"version" => 2, "value" => pack(value)})

  def decode(bytes) when is_binary(bytes) do
    case Jason.decode(bytes) do
      {:ok, %{"version" => version, "value" => value}} when version in [1, 2] ->
        {:ok, unpack(value, version)}

      _ ->
        {:error, :unsupported_storage_format}
    end
  rescue
    _error in [ArgumentError, KeyError, FunctionClauseError] -> {:error, :corrupt_storage_value}
  end

  defp pack(value)
       when is_nil(value) or is_boolean(value) or is_integer(value) or is_binary(value), do: value

  defp pack(value) when is_atom(value),
    do: %{"$atom" => Atom.to_string(Map.fetch!(@names, Atom.to_string(value)))}

  defp pack(value) when is_list(value), do: Enum.map(value, &pack/1)

  defp pack(value) when is_tuple(value),
    do: %{"$tuple" => value |> Tuple.to_list() |> Enum.map(&pack/1)}

  defp pack(%module{} = value) when module in @modules,
    do: %{"$struct" => Atom.to_string(module), "fields" => pack(Map.from_struct(value))}

  defp pack(value) when is_map(value) and not is_struct(value),
    do: %{"$map" => Enum.map(value, fn {key, item} -> [pack(key), pack(item)] end)}

  defp unpack(value, _version)
       when is_nil(value) or is_boolean(value) or is_integer(value) or is_binary(value), do: value

  defp unpack(value, version) when is_list(value), do: Enum.map(value, &unpack(&1, version))

  defp unpack(%{"$atom" => name} = tagged, _version) when map_size(tagged) == 1,
    do: Map.fetch!(@names, name)

  defp unpack(%{"$tuple" => values} = tagged, version) when map_size(tagged) == 1,
    do: values |> Enum.map(&unpack(&1, version)) |> List.to_tuple()

  defp unpack(%{"$struct" => name, "fields" => fields} = tagged, version)
       when map_size(tagged) == 2 do
    module = Map.fetch!(@registry, name)
    fields = unpack(fields, version)
    expected = Map.keys(module.__struct__()) -- [:__struct__]
    legacy = expected -- [:judgment_revision, :decisions, :commands]

    valid =
      Enum.sort(Map.keys(fields)) == Enum.sort(expected) or
        (version == 1 and module == Intent and Enum.sort(Map.keys(fields)) == Enum.sort(legacy))

    unless valid, do: raise(ArgumentError, "invalid stored fields")
    struct!(module, fields)
  end

  defp unpack(%{"$map" => entries} = tagged, version) when map_size(tagged) == 1 do
    pairs =
      Enum.map(entries, fn [key, value] -> {unpack(key, version), unpack(value, version)} end)

    result = Map.new(pairs)
    if map_size(result) != length(entries), do: raise(ArgumentError, "duplicate stored keys")
    result
  end
end
