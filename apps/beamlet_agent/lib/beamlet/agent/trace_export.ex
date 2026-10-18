defmodule Beamlet.Agent.TraceExport do
  @moduledoc "Format-2, bounded offline trace packages. Begin captures fixed Agent/Operation high waters before writing pages."
  alias Beamlet.Agent.{Reducer, TraceSnapshot, TraceVerifier}
  alias Beamlet.Storage.{Codec, Records, References}

  @version 2
  @files ~w(events inputs operations definition)
  @max_bytes 33_554_432

  def begin(repo, scope) do
    id = if is_map(scope), do: scope[:agent_id], else: scope

    with {:ok, _} <- Records.uuid(id),
         {:ok, snapshot} <- TraceSnapshot.capture(repo, id) do
      {:ok,
       Map.merge(snapshot, %{repo: repo, agent_id: id, history_seq: snapshot.agent["history_seq"]})}
    end
  end

  def export(repo, scope, policy) do
    with {:ok, fixed} <- begin(repo, scope), do: write(fixed, policy)
  end

  def write(fixed, policy) do
    with {:ok, policy} <- policy(policy),
         :ok <- empty_directory(policy.dir),
         {:ok, summaries} <- write_files(fixed, policy),
         {:ok, artifacts} <- write_artifacts(fixed, policy),
         manifest = manifest(fixed, policy, summaries, artifacts),
         :ok <- file_write(Path.join(policy.dir, "manifest.json"), Jason.encode!(manifest)) do
      {:ok, manifest}
    end
  end

  defp policy(policy) when is_list(policy) do
    if Keyword.keyword?(policy), do: policy(Map.new(policy)), else: {:error, :invalid_data}
  end

  defp policy(policy) when is_map(policy) do
    page = policy[:page] || 100
    bytes = policy[:page_bytes] || 1_048_576
    redaction = policy[:redaction] || :none

    cond do
      not valid_dir?(policy[:dir]) ->
        {:error, :invalid_data}

      not valid_page_bounds?(page, bytes) ->
        {:error, :invalid_data}

      exceeds_page_bounds?(page, bytes) ->
        {:error, :limit}

      redaction not in [:none, :drop_content] ->
        {:error, :invalid_data}

      true ->
        {:ok, %{dir: policy.dir, page: page, page_bytes: bytes, redaction: redaction}}
    end
  end

  defp policy(_), do: {:error, :invalid_data}

  defp valid_dir?(dir), do: is_binary(dir) and byte_size(dir) in 1..1024
  defp exceeds_page_bounds?(page, bytes), do: page > 500 or bytes > 4_194_304

  defp valid_page_bounds?(page, bytes),
    do: is_integer(page) and page >= 1 and is_integer(bytes) and bytes >= 4096

  defp records(fixed),
    do: %{
      "events" => fixed.events,
      "inputs" => fixed.inputs,
      "operations" => fixed.operations,
      "definition" => [fixed.agent]
    }

  defp write_files(fixed, policy) do
    Enum.reduce_while(records(fixed), {:ok, %{}}, fn {name, rows}, {:ok, acc} ->
      case write_lines(name, rows, policy) do
        {:ok, summary} -> {:cont, {:ok, Map.put(acc, name, summary)}}
        error -> {:halt, error}
      end
    end)
  end

  defp write_lines(name, rows, policy) do
    path = Path.join(policy.dir, name <> ".jsonl")

    result =
      File.open(path, [:write, :binary], fn io ->
        rows
        |> Enum.chunk_every(policy.page)
        |> Enum.reduce_while(
          {:ok, %{count: 0, hash: :crypto.hash_init(:sha256), oversized: []}},
          fn page, {:ok, state} -> reduce_outcome(write_page(io, page, name, policy, state)) end
        )
      end)

    case result do
      {:ok, {:ok, state}} ->
        {:ok,
         %{
           "count" => state.count,
           "sha256" => digest(state.hash),
           "oversized_records" => state.oversized
         }}

      _ ->
        {:error, :invalid_data}
    end
  end

  defp write_page(io, rows, name, policy, state) do
    Enum.reduce_while(rows, {:ok, state}, fn row, {:ok, acc} ->
      with {:ok, bytes} <- Codec.encode(redact(name, row, policy.redaction), :event),
           :ok <- IO.binwrite(io, [bytes, ?\n]) do
        oversized = oversized(bytes, policy, name, acc)

        {:cont,
         {:ok,
          %{
            acc
            | count: acc.count + 1,
              hash: :crypto.hash_update(acc.hash, [bytes, ?\n]),
              oversized: oversized
          }}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp oversized(bytes, policy, name, acc) do
    if byte_size(bytes) > policy.page_bytes,
      do: [%{"file" => name, "index" => acc.count} | acc.oversized],
      else: acc.oversized
  end

  defp reduce_outcome({:ok, next}), do: {:cont, {:ok, next}}
  defp reduce_outcome(error), do: {:halt, error}

  defp redact(_, row, :none), do: row

  defp redact(name, row, :drop_content) when name in ~w(events inputs),
    do: row |> Map.put("payload", %{"redacted" => true}) |> Map.put("redacted", ["payload"])

  defp redact("definition", row, :drop_content),
    do: row |> Map.put("definition", %{}) |> Map.put("redacted", ["definition"])

  defp redact("operations", row, :drop_content),
    do: %{
      "operation" => Map.drop(row["operation"], ~w(description accepted_result)),
      "redacted" => ~w(description accepted_result attempt evidence)
    }

  defp write_artifacts(_fixed, %{redaction: :drop_content}), do: {:ok, []}

  defp write_artifacts(fixed, policy) do
    with :ok <- mkdir(Path.join(policy.dir, "artifacts")) do
      Enum.reduce_while(fixed.artifacts, {:ok, []}, &write_artifact(&1, &2, policy.dir))
    end
  end

  defp write_artifact(artifact, {:ok, acc}, dir) do
    case file_write(Path.join([dir, "artifacts", artifact.id <> ".bin"]), artifact.content) do
      :ok ->
        {:cont,
         {:ok,
          acc ++
            [
              %{
                "id" => artifact.id,
                "digest" => artifact.digest,
                "size" => artifact.size,
                "media_type" => artifact.media_type
              }
            ]}}

      error ->
        {:halt, error}
    end
  end

  defp manifest(fixed, policy, summaries, artifacts) do
    %{
      "format" => "beamlet.trace",
      "export_version" => @version,
      "agent_id" => fixed.agent_id,
      "authority_id" => fixed.agent["authority_id"],
      "high_water" => %{
        "history_seq" => fixed.history_seq,
        "operations" =>
          Map.new(fixed.operations, &{&1["operation"]["id"], &1["operation"]["history_seq"]})
      },
      "ordering" => "per_scope_sequence",
      "files" => summaries,
      "artifacts" => artifacts,
      "missing" => fixed.missing,
      "history_complete" => fixed.missing == [] and policy.redaction == :none,
      "redaction" => %{
        "policy" => to_string(policy.redaction),
        "restorable" => policy.redaction == :none
      },
      "page_policy" => %{"page" => policy.page, "page_bytes" => policy.page_bytes},
      "provenance" => %{
        "fork" => fixed.control["fork"],
        "performed_operations" =>
          Enum.count(fixed.operations, &(&1["operation"]["owner_agent_id"] == fixed.agent_id)),
        "inherited_references" => length(fixed.control["inheritance"]["sources"]),
        "inherited_counted_as_execution" => false,
        "parent_history_required" => false
      }
    }
  end

  def verify(dir) do
    with {:ok, bytes} <- read_file(Path.join(dir, "manifest.json"), 4_194_304),
         {:ok, manifest} <- decode(bytes),
         :ok <- header(manifest),
         :ok <- package_budget(dir, manifest),
         {:ok, files} <- verify_files(dir, manifest),
         {:ok, artifacts} <- verify_artifacts(dir, manifest),
         :ok <- content(manifest, files, artifacts),
         complete = manifest["missing"] == [] and manifest["redaction"]["restorable"],
         true <- manifest["history_complete"] == complete do
      {:ok,
       %{
         "events" => length(files["events"]),
         "operations" => length(files["operations"]),
         "artifacts" => map_size(artifacts),
         "history_complete" => complete,
         "execution_authority" => "none"
       }}
    else
      false -> {:error, :inconsistent_manifest}
      error -> error
    end
  end

  defp header(%{"export_version" => version}) when version != @version,
    do: {:error, {:unsupported_export_version, version}}

  defp header(m) when is_map(m) do
    if valid_identity?(m) and valid_collections?(m) and valid_highwater?(m["high_water"]),
      do: :ok,
      else: {:error, :invalid_data}
  end

  defp valid_identity?(m),
    do:
      m["format"] == "beamlet.trace" and Codec.uuid?(m["agent_id"]) and
        Codec.uuid?(m["authority_id"])

  defp valid_collections?(m) do
    is_map(m["files"]) and Enum.sort(Map.keys(m["files"])) == Enum.sort(@files) and
      Enum.all?(Map.values(m["files"]), &is_map/1) and
      is_list(m["missing"]) and Enum.all?(m["missing"], &is_map/1) and
      valid_artifact_list?(m["artifacts"]) and
      is_map(m["redaction"]) and is_boolean(m["redaction"]["restorable"])
  end

  defp valid_artifact_list?(list) when is_list(list) and length(list) <= 1024,
    do: Enum.all?(list, &(is_map(&1) and Codec.uuid?(&1["id"])))

  defp valid_artifact_list?(_), do: false

  defp package_budget(dir, manifest) do
    paths =
      Enum.map(@files, &Path.join(dir, &1 <> ".jsonl")) ++
        Enum.map(manifest["artifacts"], &Path.join([dir, "artifacts", &1["id"] <> ".bin"]))

    Enum.reduce_while(paths, {:ok, 0}, fn path, {:ok, bytes} ->
      case File.lstat(path) do
        {:ok, %File.Stat{type: :regular, size: size}} when bytes + size <= @max_bytes ->
          {:cont, {:ok, bytes + size}}

        _ ->
          {:halt, {:error, {:missing_or_oversize_file, Path.basename(path)}}}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp valid_highwater?(%{"history_seq" => seq, "operations" => operations}),
    do: is_integer(seq) and seq in 1..100_000 and is_map(operations)

  defp valid_highwater?(_), do: false

  defp verify_files(dir, manifest) do
    Enum.reduce_while(@files, {:ok, %{}}, fn name, {:ok, acc} ->
      with {:ok, bytes} <- read_file(Path.join(dir, name <> ".jsonl"), @max_bytes),
           true <- Codec.hash(bytes) == manifest["files"][name]["sha256"],
           {:ok, rows} <- lines(bytes),
           true <- length(rows) == manifest["files"][name]["count"] do
        {:cont, {:ok, Map.put(acc, name, rows)}}
      else
        false -> {:halt, {:error, :digest_or_count_mismatch}}
        error -> {:halt, error}
      end
    end)
  end

  defp lines(bytes) do
    bytes
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
      case Codec.decode(line, :event) do
        {:ok, row} when is_map(row) -> {:cont, {:ok, [row | acc]}}
        _ -> {:halt, {:error, :invalid_line}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp verify_artifacts(dir, manifest) do
    Enum.reduce_while(manifest["artifacts"], {:ok, %{}}, fn a, {:ok, acc} ->
      with true <- is_map(a) and Codec.uuid?(a["id"]),
           {:ok, bytes} <- read_file(Path.join([dir, "artifacts", a["id"] <> ".bin"]), 16_777_216),
           true <- byte_size(bytes) == a["size"] and Codec.hash(bytes) == a["digest"] do
        {:cont, {:ok, Map.put(acc, a["id"], bytes)}}
      else
        _ -> {:halt, {:error, :artifact_missing_or_corrupt}}
      end
    end)
  end

  defp content(m, files, artifacts) do
    events = files["events"]

    with true <- Enum.map(events, & &1["seq"]) == Enum.to_list(1..m["high_water"]["history_seq"]),
         true <- Enum.all?(events, &(&1["scope_id"] == m["agent_id"])),
         true <-
           length(files["definition"]) == 1 and hd(files["definition"])["id"] == m["agent_id"] do
      verify_content(m, files, artifacts)
    else
      _ -> {:error, :invalid_history}
    end
  end

  defp verify_content(
         %{"redaction" => %{"policy" => "drop_content", "restorable" => false}},
         files,
         artifacts
       ) do
    if map_size(artifacts) == 0 and
         Enum.all?(List.flatten(Map.values(files)), &Map.has_key?(&1, "redacted")),
       do: :ok,
       else: {:error, :inconsistent_manifest}
  end

  defp verify_content(
         %{"redaction" => %{"policy" => "none", "restorable" => true}} = m,
         files,
         artifacts
       ) do
    with {:ok, control} <- Reducer.replay(Reducer.new(m["agent_id"]), files["events"]),
         true <- Enum.all?(files["operations"], &valid_operation_record?/1),
         true <-
           Map.new(files["operations"], &{&1["operation"]["id"], &1["operation"]["history_seq"]}) ==
             m["high_water"]["operations"],
         {:ok, ids} <- References.ids(Map.values(files)),
         true <- covered_artifacts?(ids, artifacts, m["missing"]),
         true <- covered_operations?(control, files["operations"], m["missing"]),
         :ok <- TraceVerifier.closure(control, files, artifacts, m["missing"]) do
      :ok
    else
      _ -> {:error, :invalid_reference}
    end
  end

  defp verify_content(_, _, _), do: {:error, :inconsistent_manifest}

  defp valid_operation_record?(
         %{
           "operation" => op,
           "prepared_event" => prepared,
           "accepted_event" => accepted
         } = row
       ),
       do:
         TraceSnapshot.valid_operation(op, prepared, accepted) == :ok and
           TraceSnapshot.valid_evidence(row) == :ok

  defp valid_operation_record?(_), do: false

  defp covered_artifacts?(ids, artifacts, missing),
    do: Enum.all?(ids, &(Map.has_key?(artifacts, &1) or omitted?(missing, "artifact", &1)))

  defp covered_operations?(control, rows, missing) do
    ids = Enum.map(rows, & &1["operation"]["id"])

    required =
      Enum.map(control["pending"] ++ control["consumed"], & &1["operation_id"]) ++
        Enum.flat_map(control["inheritance"]["closure"], fn ref ->
          if ref["type"] == "inherited_result", do: [ref["reference"]["operation_id"]], else: []
        end)

    Enum.all?(required, &(&1 in ids or omitted?(missing, "operation", &1)))
  end

  defp omitted?(missing, kind, id),
    do: Enum.any?(missing, &(&1["kind"] == kind and &1["id"] == id))

  defp empty_directory(dir) do
    with :ok <- mkdir(dir),
         {:ok, []} <- File.ls(dir),
         do: :ok,
         else: (_ -> {:error, :export_directory_not_empty})
  end

  defp mkdir(dir), do: normalize_file(File.mkdir_p(dir))
  defp file_write(path, bytes), do: normalize_file(File.write(path, bytes))
  defp normalize_file(:ok), do: :ok
  defp normalize_file(_), do: {:error, :invalid_data}

  defp read_file(path, limit) do
    with {:ok, %File.Stat{type: :regular, size: size}} <- File.lstat(path),
         true <- size <= limit,
         {:ok, bytes} <- File.read(path) do
      {:ok, bytes}
    else
      _ -> {:error, {:missing_or_oversize_file, Path.basename(path)}}
    end
  end

  defp decode(bytes) do
    case Jason.decode(bytes) do
      {:ok, m} when is_map(m) -> {:ok, m}
      _ -> {:error, :invalid_data}
    end
  end

  defp digest(hash), do: hash |> :crypto.hash_final() |> Base.encode16(case: :lower)
end
