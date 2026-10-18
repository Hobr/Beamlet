defmodule Beamlet.Agent.TraceExport do
  @moduledoc """
  Bounded, read-only trace export of one committed scope.

  `begin/2` fixes the scope's high-water mark first (the Agent's committed
  history sequence and its newest checkpoint timestamp). `write/2` then pages
  immutable records with short read transactions and keyset pagination, and
  streams `events.jsonl`, `checkpoints.jsonl`, referenced artifacts and a
  versioned `manifest.json`; appends made after `begin/2` cannot enter the range.

  Events keep their original scope/sequence/`recorded_at`; there is no invented
  cross-Agent order. Entries inherited from another Agent keep their source
  markers and are reported as inherited, never counted as this Agent's work. A
  fork source's own history is not assembled recursively: it is reported as
  external, and anything else not included is reported as missing.

  `verify/1` validates a manifest, its file digests and its JSONL lines without
  executing any historical code; it grants no import or execution authority. A
  record larger than the page byte budget is written whole on its own line and
  listed in the manifest's `oversized_records`; a page never splits a record.
  """
  alias Beamlet.Storage.{AgentRecords, Artifacts, Codec, History, Records}

  @export_version 1
  @format "beamlet.trace"
  @page_default 100
  @page_bytes 1_048_576
  @min_page_bytes 4_096
  @max_page_bytes 4_194_304
  @max_artifacts 64
  @line_limit 4_259_840
  @event_keys ~w(scope_id seq type schema_version payload recorded_at)
  @checkpoint_keys ~w(id agent_id continuation schema_version digest safe_to_fork recorded_at data)

  @doc """
  Fixes the export range: the Agent identity, fork provenance, committed history
  sequence and the newest checkpoint timestamp at this moment.
  """
  def begin(repo, scope) do
    with true <- is_atom(repo) and not is_nil(repo),
         {:ok, agent_id} <- scope_id(scope),
         {:ok, fetched} <- AgentRecords.fetch(repo, agent_id),
         agent = fetched["agent"],
         head = fetched["head_checkpoint"],
         {:ok, through} <- checkpoint_through(head) do
      {:ok,
       %{
         repo: repo,
         agent_id: agent_id,
         authority_id: agent["authority_id"],
         history_seq: agent["history_seq"],
         checkpoint_through: through,
         fork: %{
           "forked_from_agent_id" => agent["forked_from_agent_id"],
           "forked_from_checkpoint_id" => agent["forked_from_checkpoint_id"]
         }
       }}
    else
      false -> {:error, :invalid_data}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Fixes the range and writes the export in one call."
  def export(repo, scope, policy) do
    with {:ok, fixed} <- begin(repo, scope), do: write(fixed, policy)
  end

  @doc """
  Streams the fixed range into `policy.dir` and returns the manifest. Policy keys:
  `:dir` (required), `:page` (1..500), `:page_bytes` (4096..4 MiB) and
  `:redaction` (`:none` or `:drop_content`).
  """
  def write(fixed, policy) do
    with {:ok, policy} <- export_policy(policy),
         :ok <- prepare_dir(policy.dir),
         {:ok, events} <- stream_events(fixed, policy),
         {:ok, checkpoints} <- stream_checkpoints(fixed, policy),
         {:ok, artifacts} <- copy_artifacts(fixed, policy) do
      manifest = manifest(fixed, policy, events, checkpoints, artifacts)
      write_manifest(policy.dir, manifest)
    end
  end

  defp write_manifest(dir, manifest) do
    path = Path.join(dir, "manifest.json")

    with {:ok, bytes} <- encode(manifest) do
      case File.write(path, bytes) do
        :ok -> {:ok, manifest}
        {:error, _reason} -> {:error, :invalid_data}
      end
    end
  end

  @doc """
  Read-only verification of an export directory: manifest shape and version,
  per-file SHA-256, JSONL line shape and per-scope sequence order, and artifact
  digests/sizes. Never loads or executes historical code and grants no authority.
  """
  def verify(dir) do
    with {:ok, manifest} <- read_manifest(dir),
         {:ok, events} <- verify_events(dir, manifest),
         {:ok, checkpoints} <- verify_checkpoints(dir, manifest),
         {:ok, artifacts} <- verify_artifacts(dir, manifest),
         :ok <- consistent_completeness(manifest, events) do
      {:ok,
       %{
         "events" => events,
         "checkpoints" => checkpoints,
         "artifacts" => artifacts,
         # Recomputed from the verified facts rather than echoed: a hand-edited
         # manifest must not turn an incomplete package into a complete one.
         "history_complete" => recomputed_complete?(manifest, events),
         "redaction" => manifest["redaction"],
         "execution_authority" => "none"
       }}
    end
  end

  # The manifest carries no self-digest, so its honesty fields are cross-checked
  # against the verified content instead of being trusted.
  defp consistent_completeness(manifest, events) do
    claimed = manifest["history_complete"] == true
    actual = recomputed_complete?(manifest, events)

    if claimed == actual, do: :ok, else: {:error, :inconsistent_manifest}
  end

  defp recomputed_complete?(manifest, events) do
    manifest["missing"] == [] and
      get_in(manifest, ["counts", "events"]) == events and
      get_in(manifest, ["high_water", "history_seq"]) == events and
      get_in(manifest, ["redaction", "restorable"]) != false
  end

  ## High-water fix

  defp scope_id(%{agent_id: agent_id}), do: Records.uuid(agent_id)

  defp scope_id(agent_id) when is_binary(agent_id),
    do: Records.uuid(agent_id)

  defp scope_id(_), do: {:error, :invalid_data}

  defp checkpoint_through(nil), do: {:ok, nil}

  defp checkpoint_through(%{"recorded_at" => recorded_at}) when is_binary(recorded_at) do
    case DateTime.from_iso8601(recorded_at) do
      {:ok, at, _offset} -> {:ok, at}
      _ -> {:error, :invalid_data}
    end
  end

  defp checkpoint_through(_), do: {:error, :invalid_data}

  ## Events

  defp stream_events(fixed, policy) do
    path = Path.join(policy.dir, "events.jsonl")

    state = %{
      path: path,
      io: nil,
      hash: :crypto.hash_init(:sha256),
      count: 0,
      bytes: 0,
      cursor: 0,
      oversized: [],
      inherited: 0,
      performed: 0,
      redacted: 0,
      policy: policy,
      agent_id: fixed.agent_id
    }

    path
    |> File.open([:write, :binary], fn io ->
      page(%{state | io: io}, fixed) |> write_result()
    end)
    |> stream_outcome()
  end

  defp page(state, fixed) do
    opts = [
      after_seq: state.cursor,
      through_seq: fixed.history_seq,
      limit: state.policy.page,
      max_bytes: state.policy.page_bytes
    ]

    case History.event_page(fixed.repo, fixed.agent_id, opts) do
      {:ok, page} ->
        state = %{state | oversized: state.oversized ++ oversized_event(page)}
        continue_events(page, state, fixed)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp continue_events(page, state, fixed) do
    case reduce_writes(page["events"], state, &write_event/2) do
      {:ok, state} ->
        next = page["next_cursor"]
        empty? = page["events"] == []

        cond do
          is_nil(next) or empty? -> {:ok, state}
          next <= state.cursor -> {:error, :conflict}
          true -> page(%{state | cursor: next}, fixed)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_event(event, state) do
    line = event_line(event, state.policy.redaction)

    with {:ok, bytes} <- encode(line),
         :ok <- IO.binwrite(state.io, [bytes, ?\n]) do
      {:ok,
       %{
         state
         | count: state.count + 1,
           bytes: state.bytes + byte_size(bytes) + 1,
           hash: :crypto.hash_update(state.hash, [bytes, ?\n]),
           inherited: state.inherited + if(event["origin"] == "inherited", do: 1, else: 0),
           performed: state.performed + if(event["origin"] == "inherited", do: 0, else: 1),
           redacted: state.redacted + if(state.policy.redaction == :drop_content, do: 1, else: 0)
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # A record above the page byte budget is written whole on its own line; the
  # manifest names it instead of splitting or silently truncating it.
  defp oversized_event(%{"over_budget" => true, "events" => [event | _]}) do
    [%{"kind" => "oversized_record", "seq" => event["seq"]}]
  end

  defp oversized_event(_page), do: []

  defp reduce_writes(records, state, writer) do
    Enum.reduce_while(records, {:ok, state}, fn record, {:ok, acc} ->
      case writer.(record, acc) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp write_result({:ok, state}) do
    {:ok,
     %{
       count: state.count,
       bytes: state.bytes,
       digest: digest(state.hash),
       oversized: state.oversized,
       inherited: Map.get(state, :inherited, 0),
       performed: Map.get(state, :performed, 0),
       redacted: Map.get(state, :redacted, 0)
     }}
  end

  defp write_result({:error, reason}), do: {:error, reason}

  defp event_line(event, :none),
    do:
      Map.take(
        event,
        @event_keys ++
          [
            "turn_id",
            "operation_id",
            "causation_id",
            "dedupe_key",
            "source_agent_id",
            "source_event_id",
            "origin"
          ]
      )

  defp event_line(event, :drop_content) do
    event
    |> Map.take(
      @event_keys ++
        [
          "turn_id",
          "operation_id",
          "causation_id",
          "source_agent_id",
          "source_event_id",
          "origin"
        ]
    )
    |> Map.put("payload", %{"redacted" => true})
    |> Map.put("redacted", ["payload"])
  end

  ## Checkpoints

  defp stream_checkpoints(fixed, policy) do
    path = Path.join(policy.dir, "checkpoints.jsonl")

    state = %{
      io: nil,
      hash: :crypto.hash_init(:sha256),
      count: 0,
      bytes: 0,
      cursor: nil,
      policy: policy,
      oversized: [],
      redacted: 0
    }

    path
    |> File.open([:write, :binary], fn io ->
      checkpoint_pages(%{state | io: io}, fixed) |> write_result()
    end)
    |> stream_outcome()
  end

  # File.open/3 wraps the callback's value; only a complete stream is a success.
  defp stream_outcome({:ok, {:ok, summary}}), do: {:ok, summary}
  defp stream_outcome({:ok, {:error, reason}}), do: {:error, reason}
  defp stream_outcome({:ok, _other}), do: {:error, :invalid_data}
  defp stream_outcome(_), do: {:error, :invalid_data}

  defp checkpoint_pages(state, fixed) do
    opts = [
      after: state.cursor,
      through_recorded_at: fixed.checkpoint_through,
      limit: state.policy.page,
      max_bytes: state.policy.page_bytes
    ]

    case History.checkpoint_page(fixed.repo, fixed.agent_id, opts) do
      {:ok, page} ->
        state = %{state | oversized: state.oversized ++ oversized_checkpoint(page)}
        continue_checkpoints(page, state, fixed)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp continue_checkpoints(page, state, fixed) do
    case reduce_writes(page["checkpoints"], state, &write_checkpoint/2) do
      {:ok, state} ->
        next = page["next_cursor"]

        if is_nil(next) or page["checkpoints"] == [],
          do: {:ok, state},
          else: checkpoint_pages(%{state | cursor: next}, fixed)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_checkpoint(checkpoint, state) do
    line = checkpoint_line(checkpoint, state.policy.redaction)

    with {:ok, bytes} <- encode(line),
         :ok <- IO.binwrite(state.io, [bytes, ?\n]) do
      {:ok,
       %{
         state
         | count: state.count + 1,
           bytes: state.bytes + byte_size(bytes) + 1,
           hash: :crypto.hash_update(state.hash, [bytes, ?\n]),
           redacted: state.redacted + if(state.policy.redaction == :drop_content, do: 1, else: 0)
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp oversized_checkpoint(%{"over_budget" => true, "checkpoints" => [checkpoint | _]}) do
    [%{"kind" => "oversized_record", "checkpoint_id" => checkpoint["id"]}]
  end

  defp oversized_checkpoint(_page), do: []

  defp checkpoint_line(checkpoint, :none), do: Map.take(checkpoint, @checkpoint_keys)

  defp checkpoint_line(checkpoint, :drop_content) do
    dropped = [
      "messages",
      "assistant",
      "results",
      "pending",
      "order",
      "consumed",
      "decision",
      "request_digest"
    ]

    checkpoint
    |> Map.take(@checkpoint_keys)
    |> Map.put("data", Map.drop(checkpoint["data"] || %{}, dropped))
    |> Map.put("redacted", dropped)
  end

  ## Artifacts

  defp copy_artifacts(fixed, policy) do
    with {:ok, fetched} <- AgentRecords.fetch(fixed.repo, fixed.agent_id) do
      directory = Path.join(policy.dir, "artifacts")
      :ok = File.mkdir_p(directory)

      refs = artifact_refs(fetched["agent"]["definition"])
      {kept, dropped} = Enum.split(refs, @max_artifacts)

      result =
        kept
        |> Enum.reduce_while(
          {:ok, %{included: [], missing: []}},
          &copy_artifact_entry(fixed.repo, directory, &1, &2)
        )

      # A cap is a stated omission, never a silent drop that still reads complete.
      with {:ok, acc} <- result do
        {:ok, %{acc | missing: acc.missing ++ omitted_artifacts(dropped)}}
      end
    end
  end

  defp omitted_artifacts(dropped) do
    Enum.map(dropped, fn id ->
      %{"kind" => "artifact_omitted", "id" => id, "limit" => @max_artifacts}
    end)
  end

  defp copy_artifact_entry(repo, directory, id, {:ok, acc}) do
    case copy_artifact(repo, id, directory) do
      {:ok, entry} -> {:cont, {:ok, %{acc | included: acc.included ++ [entry]}}}
      {:error, kind} -> {:cont, {:ok, %{acc | missing: acc.missing ++ [kind]}}}
    end
  end

  defp artifact_refs(definition) do
    definition
    |> Map.get("tools", %{})
    |> Enum.flat_map(fn {_name, reference} -> Map.get(reference, "artifact_refs", []) end)
    |> Enum.filter(&Codec.uuid?/1)
    |> Enum.uniq()
  end

  defp copy_artifact(repo, id, directory) do
    path = Path.join(directory, id <> ".bin")

    case Artifacts.fetch(repo, id) do
      {:ok, artifact} ->
        case File.write(path, artifact.content) do
          :ok ->
            {:ok,
             %{
               "id" => artifact.id,
               "digest" => artifact.digest,
               "media_type" => artifact.media_type,
               "size" => artifact.size,
               "path" => Path.join("artifacts", id <> ".bin")
             }}

          {:error, _} ->
            {:error, %{"kind" => "artifact_unwritable", "id" => id}}
        end

      {:error, :artifact_missing} ->
        {:error, %{"kind" => "artifact_missing", "id" => id}}

      {:error, _reason} ->
        {:error, %{"kind" => "artifact_corrupt", "id" => id}}
    end
  end

  ## Manifest

  defp manifest(fixed, policy, events, checkpoints, artifacts) do
    missing = artifacts.missing ++ ancestor_missing(fixed)
    complete? = missing == [] and events.count == fixed.history_seq

    redaction = redaction(policy, events, checkpoints)

    %{
      "export_version" => @export_version,
      "format" => @format,
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "authority_id" => fixed.authority_id,
      "agent_id" => fixed.agent_id,
      "scope" => %{"kind" => "agent", "id" => fixed.agent_id},
      "ordering" => "per_scope_sequence",
      "high_water" => %{
        "agent_id" => fixed.agent_id,
        "history_seq" => fixed.history_seq,
        "checkpoint_recorded_at" =>
          fixed.checkpoint_through && DateTime.to_iso8601(fixed.checkpoint_through)
      },
      "fork" => Map.put(fixed.fork, "history_included", false),
      "files" => %{
        "events" => "events.jsonl",
        "checkpoints" => "checkpoints.jsonl",
        "artifacts" => "artifacts"
      },
      "counts" => %{
        "events" => events.count,
        "checkpoints" => checkpoints.count,
        "artifacts" => length(artifacts.included)
      },
      "page_policy" => %{"page" => policy.page, "page_bytes" => policy.page_bytes},
      "digests" => %{
        "events_sha256" => events.digest,
        "checkpoints_sha256" => checkpoints.digest
      },
      "artifacts" => artifacts.included,
      "oversized_records" => events.oversized ++ checkpoints.oversized,
      "missing" => missing,
      "redaction" => redaction,
      "provenance" => %{
        "performed_entries" => events.performed,
        "inherited_entries" => events.inherited,
        "inherited_counted_as_execution" => false,
        "external" => external(fixed)
      },
      "history_complete" => complete? and redaction["restorable"]
    }
  end

  defp ancestor_missing(%{fork: %{"forked_from_agent_id" => nil}}), do: []

  defp ancestor_missing(%{fork: %{"forked_from_agent_id" => source}} = fixed) do
    [
      %{
        "kind" => "ancestor_history",
        "agent_id" => source,
        "checkpoint_id" => fixed.fork["forked_from_checkpoint_id"],
        "note" => "source history is not assembled recursively; query it explicitly"
      }
    ]
  end

  defp external(%{fork: %{"forked_from_agent_id" => nil}}), do: []

  defp external(%{fork: fork}) do
    [
      %{
        "relation" => "fork_source",
        "agent_id" => fork["forked_from_agent_id"],
        "checkpoint_id" => fork["forked_from_checkpoint_id"],
        "included" => false
      }
    ]
  end

  defp redaction(policy, events, checkpoints) do
    case policy.redaction do
      :none ->
        %{"policy" => "none", "restorable" => true, "dropped_entries" => 0}

      :drop_content ->
        %{
          "policy" => "drop_content",
          "restorable" => false,
          "dropped_entries" => events.redacted + checkpoints.redacted,
          "note" => "payload/context content was dropped and marked; restore is not claimed"
        }
    end
  end

  ## Policy

  defp export_policy(policy) when is_list(policy) do
    if Keyword.keyword?(policy), do: export_policy(Map.new(policy)), else: {:error, :invalid_data}
  end

  defp export_policy(policy) when is_map(policy) and not is_struct(policy) do
    with {:ok, dir} <- dir(policy[:dir]),
         {:ok, page} <- bounded(policy[:page] || policy["page"], @page_default, 1, 500),
         {:ok, page_bytes} <-
           bounded(
             policy[:page_bytes] || policy["page_bytes"],
             @page_bytes,
             @min_page_bytes,
             @max_page_bytes
           ),
         {:ok, redaction} <- redaction_policy(policy[:redaction] || policy["redaction"]) do
      {:ok, %{dir: dir, page: page, page_bytes: page_bytes, redaction: redaction}}
    end
  end

  defp export_policy(_), do: {:error, :invalid_data}

  defp dir(value) when is_binary(value) and byte_size(value) in 1..1024, do: {:ok, value}
  defp dir(_), do: {:error, :invalid_data}

  defp bounded(nil, default, _min, _max), do: {:ok, default}

  defp bounded(value, _default, min, max)
       when is_integer(value) and value >= min and value <= max,
       do: {:ok, value}

  defp bounded(value, _default, _min, max) when is_integer(value) and value > max,
    do: {:error, :limit}

  defp bounded(_, _, _, _), do: {:error, :invalid_data}

  defp redaction_policy(nil), do: {:ok, :none}
  defp redaction_policy(value) when value in [:none, "none"], do: {:ok, :none}

  defp redaction_policy(value) when value in [:drop_content, "drop_content"],
    do: {:ok, :drop_content}

  defp redaction_policy(_), do: {:error, :invalid_data}

  defp prepare_dir(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, _reason} -> {:error, :invalid_data}
    end
  end

  defp encode(value) do
    case Codec.encode(value, :event) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, reason}
    end
  end

  defp digest(hash), do: hash |> :crypto.hash_final() |> Base.encode16(case: :lower)

  ## Verification

  defp read_manifest(dir) do
    with true <- is_binary(dir),
         path = Path.join(dir, "manifest.json"),
         {:ok, bytes} <- read_file(path),
         {:ok, manifest} <- decode(bytes),
         :ok <- manifest_shape(manifest) do
      {:ok, manifest}
    else
      false -> {:error, :invalid_data}
      {:error, reason} -> {:error, reason}
    end
  end

  defp manifest_shape(manifest) do
    cond do
      manifest["export_version"] != @export_version ->
        {:error, {:unsupported_export_version, manifest["export_version"]}}

      not valid_manifest_header?(manifest) ->
        {:error, :invalid_data}

      not valid_manifest_collections?(manifest) ->
        {:error, :invalid_data}

      not valid_manifest_scope?(manifest) ->
        {:error, :invalid_data}

      true ->
        :ok
    end
  end

  defp valid_manifest_header?(manifest) do
    manifest["format"] == @format and Codec.uuid?(manifest["agent_id"]) and
      Codec.uuid?(manifest["authority_id"]) and is_boolean(manifest["history_complete"])
  end

  defp valid_manifest_collections?(manifest) do
    is_map(manifest["digests"]) and is_list(manifest["artifacts"]) and
      is_list(manifest["missing"]) and is_map(manifest["high_water"])
  end

  defp valid_manifest_scope?(manifest) do
    is_map(manifest["scope"]) and Codec.uuid?(manifest["scope"]["id"]) and
      is_boolean(get_in(manifest["redaction"], ["restorable"]))
  end

  defp verify_events(dir, manifest) do
    path = Path.join(dir, get_in(manifest, ["files", "events"]) || "events.jsonl")

    verify_lines(path, manifest, %{
      scope_id: manifest["scope"]["id"] || manifest["agent_id"],
      count: get_in(manifest, ["counts", "events"]),
      digest: get_in(manifest, ["digests", "events_sha256"]),
      through: manifest["high_water"]["history_seq"],
      keys: ["scope_id", "seq", "type", "recorded_at"],
      redacted: manifest["redaction"]["restorable"] == false
    })
  end

  defp verify_checkpoints(dir, manifest) do
    path = Path.join(dir, get_in(manifest, ["files", "checkpoints"]) || "checkpoints.jsonl")

    verify_lines(path, manifest, %{
      scope_id: manifest["agent_id"],
      count: get_in(manifest, ["counts", "checkpoints"]),
      digest: get_in(manifest, ["digests", "checkpoints_sha256"]),
      through: nil,
      keys: ["id", "agent_id", "continuation", "recorded_at"],
      redacted: manifest["redaction"]["restorable"] == false
    })
  end

  defp verify_lines(path, _manifest, expected) do
    state = %{
      hash: :crypto.hash_init(:sha256),
      count: 0,
      last_seq: 0,
      expected: expected,
      error: nil
    }

    result =
      path
      |> stream_lines()
      |> Enum.reduce_while(state, fn
        {:verify_error, reason}, state ->
          {:halt, %{state | error: reason}}

        chunk, state ->
          state = %{state | hash: :crypto.hash_update(state.hash, chunk)}

          case check_line(chunk, state) do
            {:ok, state} -> {:cont, state}
            {:error, reason} -> {:halt, %{state | error: reason}}
          end
      end)

    cond do
      result.error ->
        {:error, result.error}

      result.count != expected.count ->
        {:error, {:line_count_mismatch, result.count, expected.count}}

      digest(result.hash) != expected.digest ->
        {:error, :digest_mismatch}

      true ->
        {:ok, result.count}
    end
  end

  # A missing, truncated or non-regular file is exactly what the verifier exists
  # for, so report it instead of raising File.Error towards the caller.
  defp stream_lines(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} -> File.stream!(path)
      _ -> [{:verify_error, {:missing_file, Path.basename(path)}}]
    end
  end

  defp check_line(chunk, state) do
    with true <- is_binary(chunk) and byte_size(chunk) in 3..@line_limit,
         {:ok, line} when is_map(line) <- decode_line(chunk),
         :ok <- required_keys(line, state.expected.keys),
         :ok <- scope_match(line, state),
         :ok <- seq_order(line, state) do
      {:ok, %{state | count: state.count + 1, last_seq: line["seq"] || state.last_seq}}
    else
      false -> {:error, :line_too_large}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_line}
    end
  end

  defp required_keys(line, keys) do
    if Enum.all?(keys, &Map.has_key?(line, &1)),
      do: :ok,
      else: {:error, {:missing_line_key, keys}}
  end

  defp scope_match(line, %{expected: %{scope_id: scope}}) do
    if line["scope_id"] == scope or line["agent_id"] == scope,
      do: :ok,
      else: {:error, :foreign_scope}
  end

  defp seq_order(%{"seq" => seq}, %{last_seq: last, expected: %{through: through}})
       when is_integer(seq) do
    cond do
      seq <= last -> {:error, :sequence_order}
      through && seq > through -> {:error, :beyond_high_water}
      true -> :ok
    end
  end

  defp seq_order(%{"id" => _id}, _state), do: :ok
  defp seq_order(_line, _state), do: {:error, :invalid_line}

  defp verify_artifacts(_dir, %{"artifacts" => []}), do: {:ok, 0}

  defp verify_artifacts(dir, %{"artifacts" => artifacts}) when is_list(artifacts) do
    Enum.reduce_while(artifacts, {:ok, 0}, &verify_artifact(dir, &1, &2))
  end

  defp verify_artifacts(_dir, _manifest), do: {:error, :invalid_data}

  defp verify_artifact(dir, artifact, {:ok, count}) do
    path = Path.join(dir, artifact["path"] || "")

    case read_file(path) do
      {:ok, bytes} -> verify_artifact_bytes(bytes, artifact, count)
      {:error, _reason} -> {:halt, {:error, {:artifact_missing, artifact["id"]}}}
    end
  end

  defp verify_artifact_bytes(bytes, artifact, count) do
    cond do
      byte_size(bytes) != artifact["size"] ->
        {:halt, {:error, {:artifact_size, artifact["id"]}}}

      Codec.hash(bytes) != artifact["digest"] ->
        {:halt, {:error, {:artifact_digest, artifact["id"]}}}

      true ->
        {:cont, {:ok, count + 1}}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, _reason} -> {:error, :invalid_data}
    end
  end

  defp decode(bytes) do
    case Jason.decode(bytes) do
      {:ok, value} -> {:ok, value}
      _ -> {:error, :invalid_data}
    end
  end

  defp decode_line(chunk) do
    bytes = String.trim_trailing(chunk, "\n")

    case Jason.decode(bytes) do
      {:ok, value} -> {:ok, value}
      _ -> {:error, :invalid_line}
    end
  end
end
