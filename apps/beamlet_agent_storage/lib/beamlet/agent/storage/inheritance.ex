defmodule Beamlet.Agent.Storage.Inheritance do
  @moduledoc "同 authority 内的直接、不可变引用清单。构建时验证源位置，输入正文转为摘要去重 artifact，Result 保留原 Operation 所有者；验证清单不递归读取父 Agent 历史。最多 128 个有序来源、1024 个闭包引用，遍历有 5 秒期限。缺失内容明确失败，不把摘要当正文。

Direct immutable content manifests. No parent history is read when verifying a manifest."
  alias Beamlet.Storage.Artifacts
  alias Beamlet.Storage.References
  import Ecto.Query
  alias Beamlet.Agent.Storage.Codec
  alias Beamlet.Agent.Storage.History
  alias Beamlet.Agent.Storage.OperationRecords
  alias Beamlet.Agent.Storage.Schema.Event
  alias Beamlet.Storage.Schema.Artifact

  @typep state :: %{
           sources: [Beamlet.Agent.Storage.Records.object()],
           closure: [Beamlet.Agent.Storage.Records.object()],
           resolutions: Beamlet.Agent.Storage.Records.object(),
           visiting: [String.t()],
           deadline: integer()
         }
  @typep object :: Beamlet.Agent.Storage.Records.object()
  @typep result(value) :: Beamlet.Agent.Storage.Records.result(value)
  @typep check :: :ok | {:error, Beamlet.Agent.Storage.Records.error()}
  @spec source_position(module(), String.t(), map()) :: check()
  @spec timeline_entry(Event.t()) :: [object()]
  @spec verify_resolutions(module(), String.t(), map()) :: check()
  @spec resolution_outcome([object()], String.t(), object()) ::
          {:cont, :ok} | {:halt, {:error, :conflict}}
  @spec build(module(), String.t(), [object()], object(), object()) :: result(object())
  @spec collect(module(), String.t(), [object()], state()) :: result(state())
  @spec bounded_capture(module(), String.t(), object(), state()) ::
          {:ok, object(), state()} | {:error, Beamlet.Agent.Storage.Records.error()}
  @spec same_source?(object(), object()) :: boolean()
  @spec capture(module(), String.t(), object(), state()) ::
          {:ok, object(), state()} | {:error, Beamlet.Agent.Storage.Records.error()}
  @spec add(object(), state()) :: {:ok, object(), state()} | {:error, :limit}
  @spec input_artifact(module(), binary()) :: result(Artifact.t())
  @spec verify(module(), term()) :: check()
  @spec verify_closure(module(), [object()], integer()) :: check()
  @spec input(module(), object()) :: result(object())
  @spec verify_entry(module(), term(), [object()]) :: check()
  @spec operation(module(), object(), object()) :: check()
  @spec valid_resolution?(object(), Beamlet.Agent.Storage.Records.value()) :: boolean()
  @spec covered?(term(), [object()]) :: boolean()
  @spec authorized?(module(), String.t(), object(), non_neg_integer()) :: boolean()

  @max_refs 1024

  @doc "在调用方事务中核对截止 through_seq 的有序 timeline、既有继承及显式决策来源；不一致返回 conflict。"
  def source_position(repo, agent, attrs) do
    events =
      repo.all(
        from(e in Event,
          where:
            e.scope_id == ^agent and e.seq <= ^attrs.through_seq and
              e.type in ~w(input.accepted operation.result_consumed context.inherited),
          order_by: e.seq,
          limit: 130
        ),
        log: false
      )

    timeline = Enum.flat_map(events, &timeline_entry/1)
    inherited = Enum.find(events, &(&1.type == "context.inherited"))
    previous = if inherited, do: inherited.payload, else: %{"sources" => [], "closure" => []}

    if timeline == attrs.timeline and previous == attrs.inheritance and length(timeline) <= 128,
      do: verify_resolutions(repo, agent, attrs),
      else: {:error, :conflict}
  end

  defp timeline_entry(%Event{type: "input.accepted"} = e) do
    {:ok, digest} = Codec.digest(e.payload, :event)
    [%{"type" => "input", "seq" => e.seq, "event_id" => e.id, "digest" => digest}]
  end

  defp timeline_entry(%Event{type: "operation.result_consumed", payload: p}),
    do: [
      %{
        "type" => "accepted_result",
        "reference" => Map.take(p, ~w(operation_id accepted_digest consumption_kind))
      }
    ]

  defp timeline_entry(%Event{type: "context.inherited", payload: p}), do: p["sources"]

  defp verify_resolutions(repo, agent, attrs) do
    Enum.reduce_while(attrs.resolutions, :ok, fn {id, resolution}, :ok ->
      case repo.get(Event, resolution["decision_event_id"], log: false) do
        %Event{scope_id: ^agent, type: "agent.continue_decided", payload: p, seq: seq}
        when seq <= attrs.through_seq ->
          decisions = p["decision"]["resolutions"] || [p["decision"]]

          resolution_outcome(decisions, id, resolution)

        _ ->
          {:halt, {:error, :conflict}}
      end
    end)
  end

  defp resolution_outcome(decisions, id, resolution) do
    if Enum.any?(
         decisions,
         &(&1["operation_id"] == id and &1["resolution"] == resolution["resolution"])
       ), do: {:cont, :ok}, else: {:halt, {:error, :conflict}}
  end

  @doc "在外层分叉事务中构建并验证扁平 sources/closure，必要时写入摘要去重输入 artifact；来源仍归原 Agent，失败应回滚。"
  def build(repo, agent_id, timeline, previous, resolutions) do
    initial = %{
      sources: [],
      closure: previous["closure"] || [],
      resolutions: resolutions,
      visiting: [],
      deadline: System.monotonic_time(:millisecond) + 5000
    }

    with {:ok, state} <- collect(repo, agent_id, timeline, initial),
         manifest = %{"sources" => state.sources, "closure" => state.closure},
         :ok <- verify(repo, manifest) do
      {:ok, manifest}
    end
  end

  defp collect(repo, agent, sources, state) do
    Enum.reduce_while(sources, {:ok, state}, fn source, {:ok, acc} ->
      case bounded_capture(repo, agent, source, acc) do
        {:ok, direct, next} -> {:cont, {:ok, %{next | sources: next.sources ++ [direct]}}}
        error -> {:halt, error}
      end
    end)
  end

  defp bounded_capture(repo, agent, source, state) do
    existing =
      Enum.find(state.closure, &same_source?(&1, source))

    cond do
      System.monotonic_time(:millisecond) >= state.deadline -> {:error, :limit}
      existing -> {:ok, existing, state}
      true -> capture(repo, agent, source, state)
    end
  end

  defp same_source?(ref, %{"type" => "accepted_result", "reference" => r}),
    do: ref["type"] == "inherited_result" and ref["reference"] == r

  defp same_source?(ref, %{"type" => "input", "event_id" => id} = source),
    do:
      ref["type"] == "inherited_input" and ref["event_id"] == id and
        ref["digest"] == source["digest"]

  defp same_source?(ref, source), do: ref == source

  defp capture(repo, agent, %{"type" => "input"} = source, state) do
    with {:ok, event} <- History.event(repo, agent, source["seq"]),
         true <- event["id"] == source["event_id"] and event["type"] == "input.accepted",
         {:ok, bytes} <- Codec.encode(event["payload"], :event),
         true <- Codec.hash(bytes) == source["digest"],
         {:ok, artifact} <- input_artifact(repo, bytes) do
      direct =
        Map.merge(source, %{
          "type" => "inherited_input",
          "source_agent_id" => agent,
          "artifact_id" => artifact.id
        })

      add(direct, state)
    else
      false -> {:error, :invalid_reference}
      error -> error
    end
  end

  defp capture(repo, agent, %{"type" => "accepted_result", "reference" => ref}, state) do
    with {:ok, %{"operation" => op}} <- OperationRecords.fetch(repo, ref["operation_id"]),
         true <- op["owner_agent_id"] == agent,
         true <- op["id"] not in state.visiting,
         %Event{payload: payload} <-
           repo.one(
             from(e in Event,
               where:
                 e.scope_id == ^agent and
                   e.type == "operation.result_consumed" and e.operation_id == ^op["id"]
             ),
             log: false
           ),
         true <- Map.take(payload, ~w(operation_id accepted_digest consumption_kind)) == ref,
         {:ok, nested} <-
           collect(repo, agent, op["sources"], %{
             state
             | sources: [],
               visiting: [op["id"] | state.visiting]
           }) do
      direct = %{
        "type" => "inherited_result",
        "reference" => ref,
        "source_agent_id" => agent,
        "description_digest" => op["description_digest"],
        "resolution" => state.resolutions[op["id"]]
      }

      add(direct, %{nested | sources: state.sources, visiting: state.visiting})
    else
      _ -> {:error, :invalid_reference}
    end
  end

  defp capture(_repo, _agent, %{"type" => type} = source, state)
       when type in ~w(inherited_input inherited_result), do: add(source, state)

  defp capture(_, _, _, _), do: {:error, :invalid_reference}

  defp add(direct, state) do
    closure = Enum.uniq(state.closure ++ [direct])

    if length(closure) <= @max_refs,
      do: {:ok, direct, %{state | closure: closure}},
      else: {:error, :limit}
  end

  defp input_artifact(repo, bytes) do
    digest = Codec.hash(bytes)

    case repo.one(from(a in Artifact, where: a.digest == ^digest), log: false) do
      nil ->
        Artifacts.put(repo, %{
          id: Ecto.UUID.generate(),
          content: bytes,
          digest: digest,
          size: byte_size(bytes),
          media_type: "application/json",
          recorded_at: DateTime.utc_now()
        })

      artifact ->
        Artifacts.fetch(repo, artifact.id)
    end
  end

  @doc "只读验证清单成员、闭包、正文/准备/接受摘要及原所有者；不读取父 Agent 历史。超预算返回 limit，损坏或缺失引用拒绝。"
  def verify(repo, %{"sources" => sources, "closure" => closure} = manifest)
      when map_size(manifest) == 2 and is_list(sources) and is_list(closure) and
             length(sources) <= 128 and length(closure) <= @max_refs do
    deadline = System.monotonic_time(:millisecond) + 5000

    if Enum.all?(sources, &(&1 in closure)),
      do: verify_closure(repo, closure, deadline),
      else: {:error, :invalid_reference}
  end

  def verify(_, _), do: {:error, :invalid_reference}

  defp verify_closure(repo, closure, deadline) do
    Enum.reduce_while(closure, :ok, fn ref, :ok ->
      result =
        if System.monotonic_time(:millisecond) < deadline,
          do: verify_entry(repo, ref, closure),
          else: {:error, :limit}

      case result do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc "读取并校验继承输入 artifact 摘要，解码为唯一 text 字段且不超过 64 KiB 的对象。"
  def input(repo, ref) do
    with {:ok, artifact} <- Artifacts.fetch(repo, ref["artifact_id"]),
         true <- artifact.digest == ref["digest"],
         {:ok, %{"text" => text} = payload} <- Codec.decode(artifact.content, :event),
         true <-
           map_size(payload) == 1 and is_binary(text) and String.valid?(text) and
             byte_size(text) <= 65_536 do
      {:ok, payload}
    else
      false -> {:error, :invalid_reference}
      error -> error
    end
  end

  defp verify_entry(repo, %{"type" => "inherited_input"} = ref, _closure) do
    with true <-
           Enum.sort(Map.keys(ref)) == ~w(artifact_id digest event_id seq source_agent_id type),
         true <- Codec.uuid?(ref["source_agent_id"]) and Codec.uuid?(ref["event_id"]),
         true <- is_integer(ref["seq"]) and ref["seq"] > 0,
         {:ok, _} <- input(repo, ref),
         do: :ok,
         else: (_ -> {:error, :invalid_reference})
  end

  defp verify_entry(repo, %{"type" => "inherited_result"} = ref, closure) do
    with true <-
           Enum.sort(Map.keys(ref)) ==
             ~w(description_digest reference resolution source_agent_id type),
         reference when is_map(reference) <- ref["reference"],
         true <-
           Enum.sort(Map.keys(reference)) == ~w(accepted_digest consumption_kind operation_id),
         {:ok, %{"operation" => op}} <- OperationRecords.fetch(repo, reference["operation_id"]),
         true <- op["owner_agent_id"] == ref["source_agent_id"],
         true <- op["description_digest"] == ref["description_digest"],
         :ok <- operation(repo, op, ref["reference"]),
         true <- Enum.all?(op["sources"], &covered?(&1, closure)),
         true <- valid_resolution?(op, ref["resolution"]) do
      :ok
    else
      _ -> {:error, :invalid_reference}
    end
  end

  defp verify_entry(_, _, _), do: {:error, :invalid_reference}

  @doc "验证 Operation 描述与准备事件、accepted Result 与接受事件摘要，同时验证 artifact 引用；只读，不授予执行权限。"
  def operation(repo, op, ref) do
    with {:ok, digest} <- Codec.digest(op["description"], :operation),
         true <- digest == op["description_digest"],
         {:ok, prepared} <- History.operation_event(repo, op["id"], 1),
         true <- prepared["type"] == "operation.prepared" and prepared["schema_version"] == 1,
         true <- prepared["payload"]["description_digest"] == digest,
         {:ok, accepted} <- History.operation_event(repo, op["id"], 2),
         true <-
           accepted["type"] == "operation.result_accepted" and accepted["schema_version"] == 1,
         {:ok, digest} <- Codec.digest(op["accepted_result"], :result),
         true <-
           digest == ref["accepted_digest"] and digest == accepted["payload"]["accepted_digest"],
         :ok <- References.verify_read(repo, op["description"]),
         :ok <- References.verify_read(repo, op["accepted_result"]) do
      :ok
    else
      false -> {:error, :invalid_reference}
      error -> error
    end
  end

  defp valid_resolution?(%{"accepted_result" => %{"status" => status}}, resolution) do
    if status in ~w(uncertain cancelled deadline unknown),
      do:
        is_map(resolution) and resolution["resolution"] in ~w(confirmed_failed confirmed_executed),
      else: is_nil(resolution)
  end

  defp covered?(%{"type" => "input"} = source, closure),
    do:
      Enum.any?(
        closure,
        &(Map.take(&1, ~w(event_id seq digest)) == Map.take(source, ~w(event_id seq digest)))
      )

  defp covered?(%{"type" => "accepted_result", "reference" => ref}, closure),
    do: Enum.any?(closure, &(&1["type"] == "inherited_result" and &1["reference"] == ref))

  defp covered?(%{"type" => type} = source, closure)
       when type in ~w(inherited_input inherited_result),
       do: source in closure

  defp covered?(_, _), do: false

  @doc "检查来源属于指定截止序列前的 context.inherited 清单，并验证整个清单；失败返回 false。"
  def authorized?(repo, agent_id, source, through) do
    case repo.one(
           from(e in Event,
             where:
               e.scope_id == ^agent_id and
                 e.type == "context.inherited" and e.seq <= ^through
           ),
           log: false
         ) do
      %Event{payload: manifest} -> source in manifest["sources"] and verify(repo, manifest) == :ok
      _ -> false
    end
  end
end
