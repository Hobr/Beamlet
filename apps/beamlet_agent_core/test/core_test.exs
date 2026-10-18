defmodule Beamlet.Agent.CoreTest do
  use ExUnit.Case, async: true
  alias Beamlet.Agent.Core.{Context, Data, Decision, Reducer}
  @id "12345678-1234-1234-1234-123456789abc"
  @digest String.duplicate("a", 64)

  defp event(type, seq, payload) do
    %{
      "id" => @id,
      "scope_id" => @id,
      "seq" => seq,
      "schema_version" => 1,
      "type" => type,
      "payload" => payload,
      "turn_id" => @id
    }
  end

  test "reference-only replay rejects gaps, malformed normalized data and missing digest" do
    created = event("agent.created", 1, %{"definition_version" => 1})
    input = event("input.accepted", 2, %{"text" => "hello"})
    assert {:ok, state} = Reducer.reduce(Reducer.new(@id), created)
    assert {:error, :invalid_history} = Reducer.reduce(state, input)
    input = Map.put(input, "input_digest", @digest)
    assert {:ok, next} = Reducer.reduce(state, input)
    assert next["continuation"] == "await_model_result"

    assert next["timeline"] == [
             %{"type" => "input", "event_id" => @id, "seq" => 2, "digest" => @digest}
           ]

    refute inspect(next) =~ "hello"
    assert {:ok, ^next} = Reducer.replay(Reducer.new(@id), [created, input])
    assert {:error, :invalid_history} = Reducer.reduce(next, input)

    for malformed <- [
          nil,
          %{},
          Map.put(input, "payload", [1 | 2]),
          Map.put(input, "type", "made.up")
        ] do
      assert {:error, _} = Reducer.reduce(state, malformed)
    end

    assert {:error, :invalid_history} = Reducer.reduce(%{}, input)
    assert {:error, :schema_unsupported} = Reducer.decode(%{"schema_version" => 2})
  end

  test "source materials bind exact membership, order, completeness and operation identity" do
    one = %{"type" => "input", "event_id" => @id}
    two = %{"type" => "inherited_input", "event_id" => "other"}
    control = %{Reducer.new(@id) | "timeline" => [one, two]}
    a = %{"source" => one, "input" => %{"text" => "one"}}
    b = %{"source" => two, "input" => %{"text" => "two"}}
    assert {:ok, context} = Context.build(control, %{}, [a, b])

    assert context.request["messages"] == [
             %{"role" => "user", "content" => "one"},
             %{"role" => "user", "content" => "two"}
           ]

    for materials <- [[b, a], [a], [a, a], [a, b, b], [nil], [a | :bad]] do
      assert {:error, :invalid_reference} = Context.materialize(control, materials)
    end

    source = %{"type" => "accepted_result", "reference" => %{"operation_id" => @id}}
    control = %{control | "timeline" => [source]}

    assert {:error, :invalid_reference} =
             Context.materialize(control, [
               %{"source" => source, "operation" => %{"id" => "other"}}
             ])
  end

  test "stored model replies use historical catalogue and call boundary avoids newer schema" do
    reply = %{"kind" => "text", "content" => "stored", "calls" => []}
    source = %{"type" => "inherited_result", "reference" => %{"operation_id" => @id}}

    op = %{
      "id" => @id,
      "role" => "model",
      "description" => %{"payload" => %{"request" => %{"catalogue" => %{}}}},
      "accepted_result" => %{"status" => "ok", "value" => reply}
    }

    control = %{Reducer.new(@id) | "timeline" => [source]}

    assert {:error, :invalid_reference} =
             Context.materialize(control, [
               %{"source" => source, "operation" => op, "input" => %{"text" => "substitution"}}
             ])

    assert {:ok, [%{"role" => "assistant", "content" => "stored"}]} =
             Context.materialize(control, [%{"source" => source, "operation" => op}])

    assert :ok =
             Context.complete_boundary([
               %{"role" => "assistant", "calls" => [%{"id" => "call"}]},
               %{"role" => "tool", "call_id" => "call"}
             ])

    assert {:error, :unsafe_position} =
             Context.complete_boundary([%{"role" => "tool", "call_id" => "call"}])
  end

  test "pure decisions retain reply, recovery and fork classifications" do
    assert Decision.reply_position(%{kind: :text}) == "completed"
    assert Decision.reply_position(%{kind: :tool_calls}) == "reply_recorded"
    assert Decision.resume("model_prepared") == :pending
    assert Decision.resume("await_model_result") == :advance
    assert Decision.resumable?("blocked")
    assert {:error, {:unsupported_continuation, "blocked"}} = Decision.resume("blocked")
    assert Decision.safe_fork?(Reducer.new(@id))
    refute Decision.safe_fork?(%{Reducer.new(@id) | "pending" => [%{}]})
    assert Data.uuid?(@id)
    refute Data.uuid?(String.upcase(@id))
    refute Data.plain?([1 | 2])
  end

  test "prepared model consumption enforces join linkage and pause without mutating candidates" do
    created = event("agent.created", 1, %{"definition_version" => 1})
    input = event("input.accepted", 2, %{"text" => "hello"}) |> Map.put("input_digest", @digest)

    prepare =
      event("model.request_prepared", 3, %{
        "operation_id" => @id,
        "step_id" => "step-1",
        "ordinal" => 0,
        "join" => %{}
      })
      |> Map.put("operation_id", @id)

    assert {:ok, state} = Reducer.replay(Reducer.new(@id), [created, input, prepare])

    consumed =
      event("operation.result_consumed", 4, %{
        "operation_id" => @id,
        "accepted_digest" => @digest,
        "consumption_kind" => "model_result",
        "join" => %{"position" => "completed"}
      })
      |> Map.put("operation_id", @id)

    assert {:ok, complete} = Reducer.reduce(state, consumed)
    assert complete["pending"] == []
    assert complete["continuation"] == "completed"
    assert {:error, :invalid_history} = Reducer.reduce(%{state | "paused" => true}, consumed)

    assert {:error, :invalid_history} =
             Reducer.reduce(
               state,
               put_in(consumed, ["payload", "join", "position"], "await_input")
             )

    assert state["continuation"] == "model_prepared"
  end

  test "fork risk is explicit and inherited context does not become consumed work" do
    created = event("agent.created", 1, %{"definition_version" => 1})

    fork =
      event("agent.forked", 2, %{
        "source_agent_id" => @id,
        "through_seq" => 4,
        "risk" => "unconfirmed"
      })

    inherited = event("context.inherited", 3, %{"sources" => [], "closure" => []})
    assert {:ok, state} = Reducer.replay(Reducer.new(@id), [created, fork, inherited])
    assert state["paused"]
    assert state["consumed"] == []

    decision =
      event("agent.continue_decided", 4, %{
        "position" => "await_input",
        "resume_operations" => [],
        "decision" => %{"risk" => "accepted"}
      })
      |> Map.put("turn_id", nil)

    assert {:ok, cleared} = Reducer.reduce(state, decision)
    assert cleared["environment_risk"] == nil
    refute cleared["paused"]

    assert {:error, :invalid_history} =
             Reducer.reduce(state, put_in(decision, ["payload", "decision"], %{}))
  end

  test "memory observations retain safe atom reasons and uncertainty precedence" do
    assert {:error, :unresolved_execution} =
             Context.observation(%{"status" => "uncertain", "reason" => :lost}, nil)

    assert {:ok, encoded} = Context.observation(%{"status" => "error", "reason" => :lost}, nil)
    assert Jason.decode!(encoded) == %{"status" => "error", "reason" => "lost"}
    assert {:error, :invalid_reference} = Context.observation(nil, nil)

    assert {:error, :unsafe_position} =
             Context.complete_boundary([%{"role" => "assistant", "calls" => [nil]}])

    assert {:error, :invalid_history} = Reducer.replay(Reducer.new(@id), [nil | :bad])
  end

  test "nonempty inheritance validates exact input, result, and resolution shapes" do
    input = %{
      "type" => "inherited_input",
      "artifact_id" => @id,
      "event_id" => @id,
      "source_agent_id" => @id,
      "seq" => 2,
      "digest" => @digest
    }

    result = %{
      "type" => "inherited_result",
      "source_agent_id" => @id,
      "description_digest" => @digest,
      "resolution" => nil,
      "reference" => %{
        "operation_id" => @id,
        "accepted_digest" => @digest,
        "consumption_kind" => "model_result"
      }
    }

    resolution = %{"resolution" => "confirmed_failed", "decision_event_id" => @id, "seq" => 5}

    resolved = %{
      result
      | "resolution" => resolution,
        "reference" => %{result["reference"] | "consumption_kind" => "evidence_resolution"}
    }

    created = event("agent.created", 1, %{"definition_version" => 1})

    fork =
      event("agent.forked", 2, %{
        "source_agent_id" => @id,
        "through_seq" => 9,
        "risk" => "unconfirmed"
      })

    for sources <- [[input, result], [input, resolved]] do
      inherited = event("context.inherited", 3, %{"sources" => sources, "closure" => sources})
      assert {:ok, state} = Reducer.replay(Reducer.new(@id), [created, fork, inherited])
      assert state["timeline"] == sources
      assert state["pending"] == [] and state["consumed"] == []
      assert state["environment_risk"] == "unconfirmed"

      decision =
        event("agent.continue_decided", 4, %{
          "position" => "await_input",
          "resume_operations" => [],
          "decision" => %{"risk" => "accepted"}
        })
        |> Map.put("turn_id", nil)

      assert {:ok, %{"environment_risk" => nil}} = Reducer.reduce(state, decision)
    end

    malformed = [
      Map.delete(input, "artifact_id"),
      Map.put(input, "seq", 0),
      Map.put(input, "digest", "bad"),
      Map.put(input, "source_agent_id", "bad"),
      Map.put(input, "extra", true),
      Map.put(input, "artifact_id", "bad"),
      Map.put(result, "reference", %{}),
      put_in(result, ["reference", "accepted_digest"], "bad"),
      put_in(result, ["reference", "consumption_kind"], "other"),
      Map.put(result, "description_digest", "bad"),
      Map.put(result, "resolution", %{}),
      Map.put(resolved, "resolution", %{resolution | "seq" => 0}),
      Map.put(resolved, "resolution", Map.put(resolution, "extra", true))
    ]

    for bad <- malformed do
      inherited = event("context.inherited", 3, %{"sources" => [bad], "closure" => [bad]})
      assert {:error, :invalid_history} = Reducer.decode(inherited)

      assert {:error, :invalid_history} =
               Reducer.replay(Reducer.new(@id), [created, fork, inherited])
    end

    assert {:error, :invalid_history} =
             Reducer.decode(
               event("context.inherited", 3, %{"sources" => [input], "closure" => []})
             )
  end

  test "material containers do not spend description or result nesting budgets" do
    source = %{"type" => "accepted_result", "reference" => %{"operation_id" => @id}}
    control = %{Reducer.new(@id) | "timeline" => [source]}

    for depth <- [32, 33], field <- ["description", "accepted_result"] do
      nested = Enum.reduce(1..depth, 0, fn _, child -> %{"x" => child} end)

      op = %{
        "id" => @id,
        "role" => "tool",
        "tool_call_id" => "call",
        "description" => nested,
        "accepted_result" => %{"status" => "ok", "value" => %{}}
      }

      op =
        if field == "accepted_result",
          do: %{op | "description" => %{}, "accepted_result" => Map.put(nested, "status", "ok")},
          else: op

      materials = [%{"source" => source, "operation" => op}]

      if depth == 32 do
        assert {:ok, [_]} = Context.materialize(control, materials)
      else
        assert {:error, :invalid_reference} = Context.materialize(control, materials)
      end
    end

    assert {:ok, acc} = Context.start(control)
    assert {:error, :invalid_reference} = Context.messages(acc)

    assert {:error, :invalid_reference} =
             Context.append(acc, %{"source" => source, "operation" => self()})
  end

  test "direct pure decode reduce and replay retain domain depth32 and refuse unsafe payloads" do
    created = event("agent.created", 1, %{"definition_version" => 1})

    for depth <- [31, 32, 33] do
      payload = Enum.reduce(1..depth, 0, fn _, child -> %{"x" => child} end)
      selected = event("context.selected", 2, payload)

      if depth <= 32 do
        assert :ok = Reducer.decode(selected)
        assert {:ok, next} = Reducer.reduce(%{Reducer.new(@id) | "through_seq" => 1}, selected)
        assert {:ok, ^next} = Reducer.replay(Reducer.new(@id), [created, selected])
      else
        assert {:error, :invalid_history} = Reducer.decode(selected)
        assert {:error, :invalid_history} = Reducer.replay(Reducer.new(@id), [created, selected])
      end
    end

    for bad <- [%{"x" => [1 | 2]}, %{"x" => self()}, %{"x" => fn -> :ok end}] do
      selected = event("context.selected", 2, bad)
      assert {:error, :invalid_history} = Reducer.decode(selected)
      assert {:error, :invalid_history} = Reducer.replay(Reducer.new(@id), [created, selected])
    end
  end
end
