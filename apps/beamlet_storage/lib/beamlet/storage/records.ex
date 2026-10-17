defmodule Beamlet.Storage.Records do
  @moduledoc """
  Shared boundary for the record transaction facades. Validation and comparison
  helpers are pure; transaction helpers run inside the caller's already-open
  transaction. Every facade revalidates identity, stored owner and CAS inputs
  instead of trusting an upstream caller. Errors stay plain atoms from the
  stage-A taxonomy; SQL, connection and configuration detail never escape.
  """
  import Ecto.Query
  alias Beamlet.Storage.{Codec, Transaction}
  alias Beamlet.Storage.Schema.{Agent, Command, Event}

  @errors ~w(invalid_data limit conflict stale_generation schema_unsupported artifact_missing storage_unavailable storage_outcome_unknown)a
  @event_type ~r/\A[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+\z/
  @digest ~r/\A[0-9a-f]{64}\z/

  @doc "Runs one write transaction; rollback keeps the whole write set out of the dataset."
  def transact(repo, fun) do
    case Transaction.write(repo, fn -> settle(repo, fun) end) do
      {:ok, response} -> {:ok, response}
      {:error, reason} when reason in @errors -> {:error, reason}
      {:error, _} -> {:error, :storage_outcome_unknown}
    end
  rescue
    Ecto.ConstraintError -> {:error, :conflict}
    Ecto.Query.CastError -> {:error, :invalid_data}
    Ecto.ChangeError -> {:error, :invalid_data}
  end

  defp settle(repo, fun) do
    case fun.() do
      {:ok, response} -> response
      {:error, reason} when is_atom(reason) -> repo.rollback(reason)
      _ -> repo.rollback(:storage_outcome_unknown)
    end
  end

  def fields(attrs, required, optional) do
    keys = if is_map(attrs) and not is_struct(attrs), do: Map.keys(attrs)

    cond do
      is_nil(keys) -> {:error, :invalid_data}
      not Enum.all?(keys, &is_atom/1) -> {:error, :invalid_data}
      not Enum.all?(required, &Map.has_key?(attrs, &1)) -> {:error, :invalid_data}
      not Enum.all?(keys, &(&1 in required or &1 in optional)) -> {:error, :invalid_data}
      true -> {:ok, attrs}
    end
  end

  def uuid(value) do
    if Codec.uuid?(value), do: {:ok, value}, else: {:error, :invalid_data}
  end

  def optional_uuid(nil), do: {:ok, nil}
  def optional_uuid(value), do: uuid(value)

  def text(value, max) when is_binary(value) do
    if String.valid?(value) and byte_size(value) in 1..max,
      do: {:ok, value},
      else: {:error, :invalid_data}
  end

  def text(_, _), do: {:error, :invalid_data}

  def optional_text(nil, _), do: {:ok, nil}
  def optional_text(value, max), do: text(value, max)

  def count(value) when is_integer(value) and value >= 0, do: {:ok, value}
  def count(_), do: {:error, :invalid_data}

  def digest(value) when is_binary(value) do
    if Regex.match?(@digest, value), do: {:ok, value}, else: {:error, :invalid_data}
  end

  def digest(_), do: {:error, :invalid_data}

  def json(value, kind) do
    case Codec.encode(value, kind) do
      {:ok, _bytes} -> {:ok, value}
      {:error, reason} when reason in [:limit, :invalid_data] -> {:error, reason}
      _ -> {:error, :invalid_data}
    end
  end

  def enum(value, allowed) when is_atom(value) and not is_nil(value),
    do: enum(Atom.to_string(value), allowed)

  def enum(value, allowed) when is_binary(value) do
    if value in allowed, do: {:ok, value}, else: {:error, :invalid_data}
  end

  def enum(_, _), do: {:error, :invalid_data}

  def event_type(value) do
    with {:ok, value} <- text(value, 255) do
      if Regex.match?(@event_type, value), do: {:ok, value}, else: {:error, :invalid_data}
    end
  end

  def get(repo, schema, id) do
    case repo.get(schema, id, log: false) do
      nil -> {:error, :conflict}
      record -> {:ok, record}
    end
  end

  def insert(repo, changeset) do
    case repo.insert(changeset, log: false) do
      {:ok, record} -> {:ok, record}
      {:error, changeset} -> {:error, changeset_error(changeset)}
    end
  end

  def changeset_error(changeset) do
    errors =
      Enum.map(changeset.errors, fn {_field, {message, opts}} ->
        {message, Keyword.get(opts, :constraint)}
      end)

    cond do
      Enum.any?(errors, &(elem(&1, 0) == "limit")) -> :limit
      Enum.any?(errors, &(elem(&1, 1) == :unique)) -> :conflict
      true -> :invalid_data
    end
  end

  @doc "Generation is checked first: a stale instance must not learn loop by loop that its version moved."
  def cas_agent(repo, agent, expected_version, expected_generation, updates) do
    if agent.generation != expected_generation do
      {:error, :stale_generation}
    else
      query =
        from(a in Agent,
          where:
            a.id == ^agent.id and a.generation == ^expected_generation and
              a.lock_version == ^expected_version,
          update: [set: ^Keyword.put(updates, :lock_version, expected_version + 1)]
        )

      case repo.update_all(query, [], log: false) do
        {1, _} -> {:ok, expected_version + 1}
        {0, _} -> {:error, :conflict}
      end
    end
  end

  @doc "Owned Operations share the Agent history order, so their events advance the Agent counter."
  def advance_agent_history(repo, agent_id, expected_version, expected_generation) do
    with {:ok, agent} <- get(repo, Agent, agent_id) do
      seq = agent.history_seq + 1

      with {:ok, _version} <-
             cas_agent(repo, agent, expected_version, expected_generation, history_seq: seq) do
        {:ok, seq}
      end
    end
  end

  def event_changeset(attrs) do
    Event.changeset(%Event{}, attrs)
    |> Ecto.Changeset.unique_constraint([:scope_id, :dedupe_key],
      name: :events_scope_id_dedupe_key_index
    )
  end

  def command_changeset(attrs) do
    Command.changeset(%Command{}, attrs)
    |> Ecto.Changeset.unique_constraint([:scope_id, :command_id],
      name: :commands_scope_id_command_id_index
    )
  end

  @doc "Normalizes one caller-supplied history event; scope, seq and dedupe are facade-owned."
  def event_input(event) do
    with {:ok, _} <- fields(event, [:id, :type, :payload], [:causation_id]),
         {:ok, id} <- uuid(event[:id]),
         {:ok, type} <- event_type(event[:type]),
         {:ok, payload} <- json(event[:payload], :event),
         {:ok, causation} <- optional_uuid(event[:causation_id]) do
      {:ok, %{id: id, type: type, payload: payload, causation_id: causation}}
    end
  end

  def command_lookup(repo, scope_id, command_id) do
    query =
      from(c in Command, where: c.scope_id == ^scope_id and c.command_id == ^command_id)

    repo.one(query, log: false)
  end

  @doc "Plain, atom-free data: timestamps become ISO 8601 strings and struct meta is dropped."
  def plain(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def plain(nil), do: nil

  def plain(%_{} = struct) do
    struct |> Map.from_struct() |> Map.delete(:__meta__) |> plain()
  end

  def plain(%{} = map) do
    Map.new(map, fn {key, value} -> {plain_key(key), plain(value)} end)
  end

  def plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  def plain(value), do: value

  defp plain_key(key) when is_atom(key), do: Atom.to_string(key)
  defp plain_key(key), do: key
end
