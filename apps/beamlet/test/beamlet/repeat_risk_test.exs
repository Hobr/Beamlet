defmodule Beamlet.RepeatRiskTest do
  use ExUnit.Case, async: true
  alias Beamlet.{Definition, Domain, Identity, Report}
  @context %{now: 0, actor: "authority"}
  defp step(intent, command, now \\ 0) do
    {:ok, t} = Domain.transition(intent, command, %{@context | now: now})
    t
  end

  defp authorized(accepted) do
    {:ok, d} =
      Definition.new(%{
        operation: "op",
        input: nil,
        policy: :retry_once,
        repeat_accepted: accepted
      })

    {:ok, identity} = Identity.new("collection", "agent", "key")
    {:ok, t} = Domain.new_intent("intent", identity, d, @context)
    t = step(t.intent, {:create_execution, "old"})
    t = step(t.intent, {:claim, "old", "worker", "incarnation", 0, 2})
    {:claimed, token} = t.reply

    b = %{
      "operation" => "op",
      "handler" => "handler",
      "protocol" => "protocol",
      "resource" => %{"account" => "one"}
    }

    t = step(t.intent, {:authorize, token, b})
    {t.intent, token, b}
  end

  test "default denial, strict booleans and accepted Definition identity are preserved" do
    {:ok, d} = Definition.new(%{operation: "op", input: nil, policy: :retry_once})
    refute d.repeat_accepted

    for invalid <- [nil, "true", 1, :accept] do
      assert {:error, :invalid_repeat_acceptance} =
               Definition.new(%{operation: "op", input: nil, repeat_accepted: invalid})
    end

    {intent, _old, _binding} = authorized(false)
    t = step(intent, {:expire, "old"}, 2)

    assert {:error, :unsafe_retry} =
             Domain.transition(t.intent, {:replace_execution, "old", "new", "no acceptance"}, %{
               @context
               | now: 2
             })

    assert {:error, :definition_conflict} =
             Domain.resubmit(intent, intent.identity, %{d | repeat_accepted: true})
  end

  test "acceptance does not change the original resource or override StopOnFailure" do
    {intent, _old, b} = authorized(true)
    t = step(intent, {:expire, "old"}, 2)
    t = step(t.intent, {:replace_execution, "old", "new", "accepted repeat"}, 2)
    t = step(t.intent, {:claim, "new", "worker", "incarnation", 0, 2}, 2)
    {:claimed, next} = t.reply

    assert {:error, :retry_resource_mismatch} =
             Domain.transition(
               t.intent,
               {:authorize, next, %{b | "resource" => %{"account" => "other"}}},
               %{@context | now: 2}
             )

    {:ok, d} = Definition.new(%{operation: "op", input: nil, repeat_accepted: true})
    {:ok, created} = Domain.new_intent("stop", intent.identity, d, @context)
    t = step(created.intent, {:create_execution, "first"})

    assert {:error, :retry_disabled} =
             Domain.transition(
               t.intent,
               {:replace_execution, "first", "second", "repeat"},
               @context
             )
  end

  test "explicit immutable repeat acceptance permits replacement without implying the old grant stopped" do
    {intent, old, b} = authorized(true)
    t = step(intent, {:expire, "old"}, 2)
    t = step(t.intent, {:replace_execution, "old", "new", "accepted repeat"}, 2)
    assert t.intent.executions["new"].replacement.basis == :repeat_accepted
    assert t.intent.definition.repeat_accepted
    assert Domain.check_invocation(t.intent, old, %{@context | now: 2}) == :ok
    t = step(t.intent, {:claim, "new", "worker", "incarnation", 0, 2}, 2)
    {:claimed, next} = t.reply
    t = step(t.intent, {:authorize, next, %{b | "protocol" => "next"}}, 2)
    assert Domain.check_invocation(t.intent, next, %{@context | now: 100}) == :ok

    old_success = %Report{
      id: "old-success",
      token: old,
      operation: "op",
      kind: :success,
      body: "old"
    }

    t = step(t.intent, {:record_report, old_success}, 2)
    assert t.intent.outcome == nil
    failure = %Report{id: "failure", token: next, operation: "op", kind: :failure, body: "bad"}
    t = step(t.intent, {:record_report, failure}, 2)
    assert t.intent.outcome == nil

    assert {:error, :unresolved_risk} =
             Domain.transition(t.intent, {:stop_known_failure, "new"}, %{@context | now: 2})

    assert {:error, :retry_budget_exhausted} =
             Domain.transition(t.intent, {:replace_execution, "new", "third", "again"}, %{
               @context
               | now: 2
             })
  end
end
