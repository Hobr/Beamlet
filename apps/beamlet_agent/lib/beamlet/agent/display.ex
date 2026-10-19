defmodule Beamlet.Agent.Display do
  @typedoc """
  公开创建标签，精确键/UTF-8/4096 字节约束由 metadata? 校验，不代表授权。

  Public labels only; sizes, exact keys and distinct Tool IDs require metadata?/1.
  """
  @type metadata :: %{
          optional(:title) => binary(),
          optional(:preset_id) => binary(),
          optional(:option_ids) => %{
            optional(:model) => binary(),
            optional(:environment) => binary(),
            optional(:constraints) => binary(),
            optional(:tools) => [binary()]
          }
        }
  @typep annotation :: %{id: reference(), turn: Beamlet.Agent.turn()}
  @typep call :: %{id: binary(), name: binary(), arguments: binary(), truncated: boolean()}
  @typep entry :: %{
           id: reference(),
           turn: Beamlet.Agent.turn(),
           role: binary(),
           content: binary() | nil,
           call_id: binary() | nil,
           calls: [call()],
           truncated: boolean()
         }
  @typep activity :: %{
           required(:id) => reference() | binary() | non_neg_integer(),
           required(:kind) => :model | :tool | :child,
           required(:turn) => Beamlet.Agent.turn(),
           required(:status) => :pending | :admitting | :running | :starting | :completed,
           required(:placement) => :unknown,
           required(:truncated) => boolean(),
           optional(:operation) => Beamlet.Actions.OperationRef.t() | nil,
           optional(:attempt) => binary() | nil,
           optional(:child) => Beamlet.Agent.Ref.t() | nil,
           optional(:child_turn) => Beamlet.Agent.turn(),
           optional(:name) => binary(),
           optional(:arguments) => binary(),
           optional(:result) => binary() | nil,
           optional(:result_omitted) => :unsupported_content | nil
         }
  @typep display :: %{
           version: 1,
           coverage: :live_context,
           metadata: metadata(),
           entries: [entry()],
           activities: [activity()],
           omitted: %{entries: non_neg_integer(), activities: non_neg_integer()},
           truncated: boolean(),
           reasons: [atom()]
         }
  @typedoc """
  基础快照加可选 display；预算不足时可仅有标记或完全省略 display。

  Display can be omitted entirely or replaced by a budget marker; base final/progress remain open.
  """
  @type snapshot :: %{
          required(:ref) => Beamlet.Agent.Ref.t(),
          required(:turn) => Beamlet.Agent.turn(),
          required(:terminal_turn) => Beamlet.Agent.turn(),
          required(:status) => atom(),
          required(:steps) => non_neg_integer(),
          required(:final) => term(),
          required(:progress) => term(),
          optional(:display) =>
            display()
            | %{version: 1, coverage: :live_context, truncated: true, reason: :snapshot_budget}
        }
  @spec metadata?(term()) :: boolean()
  @spec option_ids?(term()) :: boolean()
  @spec labels?(term(), integer()) :: boolean()
  @spec label?(term()) :: boolean()
  @spec annotate(Beamlet.Agent.Server.state(), [Beamlet.Harness.Model.json_object()]) ::
          Beamlet.Agent.Server.state()
  @spec project(Beamlet.Agent.snapshot(), Beamlet.Agent.Server.state()) :: snapshot()
  @spec field_truncated?(entry() | activity()) :: boolean()
  @spec unsupported_content?(entry() | activity()) :: boolean()
  @spec reason([atom()], boolean(), atom()) :: [atom()]
  @spec fit(Beamlet.Agent.snapshot(), Beamlet.Agent.Server.state(), display()) :: snapshot()
  @spec compact(Beamlet.Agent.snapshot(), Beamlet.Agent.Server.state()) :: snapshot()
  @spec omit(display(), :entries | :activities) :: display()
  @spec byte_omission(display()) :: display()
  @spec entry(Beamlet.Harness.Model.json_object(), annotation()) :: entry()
  @spec call(Beamlet.Harness.Model.json_object()) :: call()
  @spec activities(Beamlet.Agent.Server.state()) :: [activity()]
  @spec model_activities(Beamlet.Agent.Server.state()) :: [activity()]
  @spec tool_activities(Beamlet.Agent.Server.state()) :: [activity()]
  @spec child_activities(Beamlet.Agent.Server.state()) :: [activity()]
  @spec completed_children(Beamlet.Agent.Server.state()) :: [activity()]
  @spec render_result(term()) :: %{
          result: binary() | nil,
          truncated: boolean(),
          result_omitted: :unsupported_content | nil
        }
  @spec pending_owner(Beamlet.Agent.Server.state(), pid()) :: Beamlet.Agent.Server.pending() | nil
  @spec tool_activity?(
          Beamlet.Agent.Server.state(),
          binary(),
          Beamlet.Agent.Server.pending() | nil,
          Beamlet.Harness.Model.json_object() | nil
        ) :: Beamlet.Agent.Server.pending() | Beamlet.Harness.Model.json_object() | boolean()
  @spec pending_tool(Beamlet.Agent.Server.state(), binary()) ::
          Beamlet.Agent.Server.pending() | nil
  @spec cond_status(term(), term()) :: :completed | :pending | :admitting
  @spec text(binary() | nil) :: {binary() | nil, boolean()}
  @spec utf8_prefix(binary()) :: binary()
  @moduledoc """
  实时上下文的有界替换视图，不能用作模型历史。最多 32 条近期消息、16 个活动，各文本字段 8192 UTF-8 字节；预算不足可只给标记或完全省略 display，消费者应清除旧视图。pending 仅表示取得 Runtime Ref，placement 当前未知。

  Bounded, replacement-only display of live Agent context, never model history.

  Optional creation metadata is a plain map with `:title` (1..128 UTF-8 bytes),
  `:preset_id` (1..128 bytes) and `:option_ids`. The latter permits only `:model`,
  `:environment`, `:constraints` (single public IDs) and `:tools` (up to 64 distinct
  IDs). IDs are UTF-8 labels, not modules or configuration. The entire metadata
  map must fit 4096 Erlang serialized bytes. Omitted metadata defaults to `%{}`.
  These trusted descriptions are not authorization or secret-echo protection.

  Version 1 exposes at most 32 recent entries and 16 current activities. Content,
  arguments (JSON text) and results are limited to 8192 UTF-8 bytes each. Coverage
  is only `:live_context`; IDs and turn references belong to the source incarnation.
  `:omitted` counts and `:reasons` describe loss, including aggregate byte pressure.
  Under extreme full-snapshot pressure, `display` can be only a compact marker
  (`version`, `coverage`, `truncated: true`, `reason: :snapshot_budget`). If even
  that cannot fit, the original base snapshot is returned without `display`;
  absence on a requested display view means complete budget omission, never an
  instruction to keep the previous display. Base final/progress stay unchanged.
  Operation activity status `:pending` means a Runtime Ref was received, not
  proof that an executor has admitted or begun the work.
  Placement is `:unknown` unless the source actually observes it (currently never).
  Render all text as untrusted content. Never feed this projection to a model.
  """

  @target 131_072
  @snapshot_limit 1_048_000
  @text_limit 8192

  @doc "校验公开标签、精确键及 4096 字节元数据上限；这些标签不独立证明授权。"
  def metadata?(value) when is_map(value) and not is_struct(value) do
    Map.keys(value) -- [:title, :preset_id, :option_ids] == [] and
      Enum.all?(value, fn
        {:option_ids, ids} -> option_ids?(ids)
        {_, text} -> label?(text)
      end) and :erlang.external_size(value) <= 4096
  end

  def metadata?(_), do: false

  defp option_ids?(ids) when is_map(ids) and not is_struct(ids) do
    Map.keys(ids) -- [:model, :tools, :environment, :constraints] == [] and
      Enum.all?(ids, fn
        {:tools, tools} ->
          labels?(tools, 64) and
            length(Enum.uniq(tools)) == length(tools)

        {_, id} ->
          label?(id)
      end)
  end

  defp option_ids?(_), do: false

  defp labels?([], _), do: true

  defp labels?([id | rest], remaining) when remaining > 0,
    do: label?(id) and labels?(rest, remaining - 1)

  defp labels?(_, _), do: false

  defp label?(s), do: is_binary(s) and byte_size(s) in 1..128 and String.valid?(s)

  # Annotations contain no transcript copy, and are bounded by the source context.
  @doc "为新增原生消息附上本实例内稳定的展示身份，不复制消息正文。"
  def annotate(s, messages) do
    additions = length(messages) - length(s.messages)
    annotations = for _ <- List.duplicate(nil, additions), do: %{id: make_ref(), turn: s.turn}
    %{s | messages: messages, display_entries: s.display_entries ++ annotations}
  end

  @doc "生成替换展示并在预算内裁剪展示项；不改变模型上下文或基础 final/progress。"
  def project(base, s) do
    entries = Enum.zip_with(s.messages, s.display_entries, &entry/2)
    activities = activities(s)

    display = %{
      version: 1,
      coverage: :live_context,
      metadata: s.display_metadata,
      entries: Enum.take(entries, -32),
      activities: Enum.take(activities, 16),
      omitted: %{
        entries: max(length(entries) - 32, 0),
        activities: max(length(activities) - 16, 0)
      },
      truncated: false,
      reasons: []
    }

    reasons =
      []
      |> reason(length(entries) > 32, :entry_limit)
      |> reason(length(activities) > 16, :activity_limit)
      |> reason(
        Enum.any?(display.entries ++ display.activities, &field_truncated?/1),
        :field_limit
      )
      |> reason(Enum.any?(display.activities, &unsupported_content?/1), :unsupported_content)

    fit(base, s, %{display | reasons: reasons, truncated: reasons != []})
  end

  defp field_truncated?(entry), do: entry.truncated and not unsupported_content?(entry)
  defp unsupported_content?(entry), do: entry[:result_omitted] == :unsupported_content

  defp reason(reasons, true, reason), do: Enum.uniq(reasons ++ [reason])
  defp reason(reasons, false, _), do: reasons

  defp fit(base, s, display) do
    snapshot = Map.put(base, :display, display)
    envelope = {:beamlet_agent, s.ref, s.sequence + 1, {:snapshot, snapshot}}

    cond do
      :erlang.external_size(display) <= @target and
          :erlang.external_size(envelope) <= @snapshot_limit ->
        snapshot

      display.entries != [] ->
        fit(base, s, omit(display, :entries))

      display.activities != [] ->
        fit(base, s, omit(display, :activities))

      display.metadata != %{} ->
        fit(base, s, %{
          display
          | metadata: %{},
            truncated: true,
            reasons: reason(display.reasons, true, :snapshot_budget)
        })

      true ->
        # A base snapshot can consume the entire old budget. Even a marker must
        # not turn that previously valid default snapshot into a new failure.
        compact(base, s)
    end
  end

  defp compact(base, s) do
    marker = %{version: 1, coverage: :live_context, truncated: true, reason: :snapshot_budget}
    snapshot = Map.put(base, :display, marker)

    if :erlang.external_size({:beamlet_agent, s.ref, s.sequence + 1, {:snapshot, snapshot}}) <=
         @snapshot_limit,
       do: snapshot,
       else: base
  end

  defp omit(%{entries: [_ | rest]} = display, :entries) do
    %{display | entries: rest, omitted: %{display.omitted | entries: display.omitted.entries + 1}}
    |> byte_omission()
  end

  defp omit(%{activities: [_ | rest]} = display, :activities) do
    %{
      display
      | activities: rest,
        omitted: %{display.omitted | activities: display.omitted.activities + 1}
    }
    |> byte_omission()
  end

  defp byte_omission(display),
    do: %{display | truncated: true, reasons: reason(display.reasons, true, :snapshot_budget)}

  defp entry(message, annotation) do
    {content, truncated} = text(message["content"])
    calls = Enum.map(message["calls"] || [], &call/1)

    Map.merge(annotation, %{
      role: message["role"],
      content: content,
      call_id: message["call_id"],
      calls: calls,
      truncated: truncated or Enum.any?(calls, & &1.truncated)
    })
  end

  defp call(call) do
    {arguments, truncated} = call["arguments"] |> Jason.encode!() |> text()
    %{id: call["id"], name: call["name"], arguments: arguments, truncated: truncated}
  end

  defp activities(s) do
    (model_activities(s) ++ tool_activities(s) ++ child_activities(s) ++ completed_children(s))
    |> Enum.sort_by(&{&1.kind, &1.id})
  end

  defp model_activities(s) do
    for {token, owner} <- s.owners,
        owner.turn == s.turn and owner.key == :model and not Map.get(owner, :completed, false) do
      pending = pending_owner(s, owner.pid)

      %{
        id: token,
        kind: :model,
        turn: owner.turn,
        status: if(pending, do: :pending, else: :admitting),
        operation: if(pending, do: pending.ref),
        attempt: if(pending, do: pending.attempt),
        placement: :unknown,
        truncated: false
      }
    end
  end

  defp tool_activities(s) do
    for c <- (s.assistant || %{})["calls"] || [],
        pending <- [pending_tool(s, c["id"])],
        result <- [s.results[c["id"]]],
        tool_activity?(s, c["id"], pending, result) do
      c = call(c)
      {result_text, truncated} = text(if(result, do: result["content"]))

      Map.merge(c, %{
        kind: :tool,
        turn: s.turn,
        status: cond_status(result, pending),
        operation: if(pending, do: pending.ref),
        attempt: if(pending, do: pending.attempt),
        result: result_text,
        placement: :unknown,
        truncated: c.truncated or truncated
      })
    end
  end

  defp child_activities(s) do
    for {id, child} <- s.children do
      %{
        id: id,
        kind: :child,
        turn: s.turn,
        status: if(Map.has_key?(child, :ref), do: :running, else: :starting),
        child: child[:ref],
        child_turn: child[:turn],
        placement: :unknown,
        truncated: false
      }
    end
  end

  defp completed_children(s) do
    for {id, result} <- s.results, s.status == :waiting do
      rendered = result.result |> elem(1) |> render_result()

      Map.merge(
        %{
          id: id,
          kind: :child,
          turn: s.turn,
          status: :completed,
          child: result.child,
          child_turn: result.turn,
          placement: :unknown
        },
        rendered
      )
    end
  end

  # Existing terminal errors may contain safe non-JSON tuples. Display reads
  # must neither inspect arbitrary terms nor crash an otherwise valid Agent.
  defp render_result(value) do
    case Jason.encode(value) do
      {:ok, json} ->
        {result, truncated} = text(json)
        %{result: result, truncated: truncated, result_omitted: nil}

      {:error, _} ->
        %{result: nil, truncated: true, result_omitted: :unsupported_content}
    end
  rescue
    _ in [Jason.EncodeError, Protocol.UndefinedError, FunctionClauseError] ->
      %{result: nil, truncated: true, result_omitted: :unsupported_content}
  end

  defp pending_owner(s, pid),
    do: Enum.find_value(s.pending, fn {_, p} -> if p.owner == pid, do: p end)

  defp tool_activity?(s, id, pending, result),
    do:
      pending || result ||
        Enum.any?(s.owners, fn {_, owner} ->
          owner.key == id and owner.turn == s.turn and not Map.get(owner, :completed, false)
        end)

  defp pending_tool(s, id),
    do: Enum.find_value(s.pending, fn {_, p} -> if p.key == id, do: p end)

  defp cond_status(result, pending) do
    cond do
      result -> :completed
      pending -> :pending
      true -> :admitting
    end
  end

  defp text(nil), do: {nil, false}
  defp text(text) when byte_size(text) <= @text_limit, do: {text, false}

  defp text(text) do
    {utf8_prefix(binary_part(text, 0, @text_limit)), true}
  end

  defp utf8_prefix(text) do
    if String.valid?(text),
      do: text,
      else: utf8_prefix(binary_part(text, 0, byte_size(text) - 1))
  end
end
