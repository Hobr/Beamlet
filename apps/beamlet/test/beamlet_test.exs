defmodule BeamletTest do
  use ExUnit.Case, async: true

  alias Beamlet.{Definition, Domain, Identity, Intent, Lease, Report, Transition}

  defp context(now \\ 10), do: %{now: now, actor: "authority-a"}

  defp new_intent(policy \\ :stop_on_failure, id \\ "intent-a") do
    {:ok, definition} =
      Definition.new(%{
        operation: "api.request.v1",
        input: %{"prompt" => "hello"},
        policy: policy
      })

    {:ok, identity} = Identity.new("collection-a", "agent-a", "call-1")
    {:ok, transition} = Domain.new_intent(id, identity, definition, context())
    transition.intent
  end

  defp step(intent, command, now \\ 10) do
    assert {:ok, %Transition{} = transition} = Domain.transition(intent, command, context(now))
    assert transition.intent.phase == :closed == (transition.intent.outcome != nil)
    if intent.outcome, do: assert(transition.intent.outcome === intent.outcome)
    transition
  end

  defp prepared(policy),
    do: step(new_intent(policy), {:create_execution, "execution-1"}).intent

  defp claimed(policy \\ :stop_on_failure) do
    transition = step(prepared(policy), {:claim, "execution-1", "worker-a", "session-1", 0, 5})
    {:claimed, token} = transition.reply
    {transition.intent, token}
  end

  defp handler_binding(completion \\ nil) do
    %{
      "operation" => "api.request.v1",
      "handler" => "example-handler.v1",
      "protocol" => "example-protocol.v1",
      "resource" => %{"account" => "account-a"},
      "completion" => completion
    }
  end

  defp authorized(policy \\ :stop_on_failure, completion \\ nil) do
    {intent, token} = claimed(policy)
    {step(intent, {:authorize, token, handler_binding(completion)}).intent, token}
  end

  defp report(token, kind \\ :success, body \\ %{"answer" => "hello"}, id \\ "report-1"),
    do: %Report{id: id, token: token, operation: "api.request.v1", kind: kind, body: body}

  defp execution(intent), do: intent.executions["execution-1"]
  defp kinds(transition), do: Enum.map(transition.events, & &1.kind)

  test "creation preserves definition and returns History materials with explicit actor/time" do
    {:ok, identity} = Identity.new("collection", "namespace", "key")
    {:ok, definition} = Definition.new(%{operation: "api.request.v1", input: nil})
    assert {:ok, transition} = Domain.new_intent("intent", identity, definition, context(123))
    assert %Intent{phase: :open, outcome: nil, definition: ^definition} = transition.intent

    assert transition.intent.idempotency_context == %{
             "collection" => "collection",
             "intent_id" => "intent"
           }

    assert [%{kind: :intent_created, actor: "authority-a", at: 123, version: 1}] =
             transition.events
  end

  test "invalid context and forged definition structs cannot enter a new Intent" do
    intent = new_intent()

    assert {:error, :invalid_context} =
             Domain.transition(intent, {:cancel, nil}, %{now: 1.0, actor: "authority"})

    assert {:error, :invalid_context} =
             Domain.transition(intent, {:cancel, nil}, %{now: 1, actor: self()})

    assert {:error, :invalid_type} =
             Domain.new_intent(
               "id",
               intent.identity,
               %{intent.definition | input: self()},
               context()
             )
  end

  test "keyed resubmission returns current facts including the original Closed result" do
    {intent, token} = authorized()
    closed = step(intent, {:record_report, report(token)}).intent
    assert {:ok, ^closed} = Domain.resubmit(closed, closed.identity, closed.definition)

    assert {:error, :definition_conflict} =
             Domain.resubmit(closed, closed.identity, %{closed.definition | input: nil})

    assert {:error, :identity_mismatch} =
             Domain.resubmit(
               closed,
               %{closed.identity | namespace: "another-agent"},
               closed.definition
             )

    assert {:error, :unkeyed_submission} =
             Domain.resubmit(closed, %{closed.identity | key: nil}, closed.definition)
  end

  test "creating the same Execution returns existing facts and never resets it" do
    {intent, _token} = authorized()
    transition = step(intent, {:create_execution, "execution-1"})
    assert transition.intent === intent
    assert transition.events == []

    assert {:error, :current_execution_exists} =
             Domain.transition(intent, {:create_execution, "execution-2"}, context())
  end

  test "claim replies can be replayed without changing generation, expiry or History" do
    {intent, token} = claimed()
    replay = step(intent, {:claim, "execution-1", "worker-a", "session-1", 0, 100}, 11)
    assert replay.reply == {:claimed, token}
    assert replay.intent === intent
    assert replay.events == []
    assert execution(replay.intent).lease.expires_at == 15
  end

  test "competing workers and old expected-generation requests cannot allocate another generation" do
    {intent, _token} = claimed()

    assert {:error, :generation_mismatch} =
             Domain.transition(
               intent,
               {:claim, "execution-1", "worker-b", "session-1", 0, 5},
               context()
             )

    assert {:error, :already_claimed} =
             Domain.transition(
               intent,
               {:claim, "execution-1", "worker-b", "session-1", 1, 5},
               context()
             )

    assert {:error, :generation_mismatch} =
             Domain.transition(
               intent,
               {:claim, "execution-1", "worker-a", "session-1", 0, 5},
               context(15)
             )
  end

  test "an unstarted expired attempt can be reclaimed, atomically invalidating the old generation" do
    {intent, old} = claimed()
    transition = step(intent, {:claim, "execution-1", "worker-b", "session-2", 1, 5}, 15)
    assert {:claimed, token} = transition.reply
    assert token.generation == 2
    assert kinds(transition) == [:lease_expired, :execution_claimed]
    assert execution(transition.intent).phase == :prepared

    assert {:error, :token_mismatch} =
             Domain.transition(
               transition.intent,
               {:authorize, old, handler_binding()},
               context(10)
             )

    assert step(transition.intent, {:authorize, token, handler_binding()}, 15).intent.phase ==
             :open
  end

  test "lease renewal updates only control facts and cannot shorten the lease" do
    {intent, token} = claimed()
    renewed = step(intent, {:renew, token, 10}, 11)
    assert execution(renewed.intent).lease.expires_at == 21
    assert renewed.events == []
    assert step(renewed.intent, {:renew, token, 1}, 12).intent === renewed.intent
  end

  test "expiry is inclusive and an authorization rejection carries the barrier to commit" do
    {intent, token} = claimed()
    rejected = step(intent, {:authorize, token, handler_binding()}, 15)
    assert rejected.reply == {:rejected, :lease_expired}
    assert kinds(rejected) == [:lease_expired]
    assert execution(rejected.intent).lease.invalidated
    assert execution(rejected.intent).authorization == nil

    assert {:error, :lease_expired} =
             Domain.transition(
               rejected.intent,
               {:authorize, token, handler_binding()},
               context(0)
             )

    assert {:error, :lease_expired} =
             Domain.transition(rejected.intent, {:renew, token, 5}, context(0))

    assert step(rejected.intent, {:expire, "execution-1"}, 0).events == []
  end

  test "expired renewal creates Unknown without changing the grant or generating Failed" do
    {intent, token} = authorized()
    rejected = step(intent, {:renew, token, 10}, 15)
    assert rejected.reply == {:rejected, :lease_expired}
    assert execution(rejected.intent).phase == :unknown
    assert execution(rejected.intent).authorization === token
    assert rejected.intent.phase == :open
    assert rejected.intent.outcome == nil
    refute Lease.valid?(execution(rejected.intent).lease, token, 0)

    assert {:error, :execution_not_prepared} =
             Domain.transition(
               rejected.intent,
               {:claim, "execution-1", "worker-b", "session-2", 1, 5},
               context(16)
             )
  end

  test "old scope or token rejection cannot expire a different current lease" do
    {intent, token} = claimed()

    assert {:error, :scope_mismatch} =
             Domain.transition(
               intent,
               {:authorize, %{token | intent_id: "other"}, handler_binding()},
               context(20)
             )

    assert {:error, :scope_mismatch} =
             Domain.transition(
               intent,
               {:authorize, %{token | collection: "other"}, handler_binding()},
               context(20)
             )

    assert {:error, :token_mismatch} =
             Domain.transition(
               intent,
               {:authorize, %{token | incarnation: "old-session"}, handler_binding()},
               context(20)
             )

    refute execution(intent).lease.invalidated
  end

  test "authorization requires a compatible serializable Handler and resource snapshot" do
    {intent, token} = claimed()

    assert {:error, :invalid_handler_binding} =
             Domain.transition(
               intent,
               {:authorize, token, %{handler_binding() | "operation" => "other.v1"}},
               context()
             )

    assert {:error, :invalid_type} =
             Domain.transition(
               intent,
               {:authorize, token, Map.put(handler_binding(), "runtime", self())},
               context()
             )

    assert execution(intent).authorization == nil
  end

  test "lost authorization replies return the original binding after expiry and closure" do
    {intent, token} = authorized()
    closed = step(intent, {:cancel, "stop"}).intent

    replay =
      step(closed, {:authorize, token, %{handler_binding() | "handler" => "new-handler.v2"}}, 100)

    assert replay.reply == {:authorized, token, handler_binding()}
    assert replay.intent === closed
    assert replay.events == []

    assert {:error, :already_authorized} =
             Domain.transition(
               closed,
               {:authorize, %{token | incarnation: "session-2"}, handler_binding()},
               context(100)
             )
  end

  test "a report cannot establish its own authorization or change the Operation" do
    {intent, token} = claimed()

    assert {:error, :unauthorized_report} =
             Domain.transition(intent, {:record_report, report(token)}, context())

    {intent, token} = authorized()

    assert {:error, :operation_mismatch} =
             Domain.transition(
               intent,
               {:record_report, %{report(token) | operation: "other.v1"}},
               context()
             )

    assert {:error, :invalid_type} =
             Domain.transition(
               intent,
               {:record_report, report(token, :success, self())},
               context()
             )

    assert {:error, :scope_mismatch} =
             Domain.transition(
               intent,
               {:record_report, report(%{token | intent_id: "other"})},
               context()
             )
  end

  test "success returns evidence, resolution, unique Outcome and closing History together" do
    {intent, token} = authorized()
    transition = step(intent, {:record_report, report(token)})
    assert transition.reply == :report_recorded
    assert transition.intent.phase == :closed
    assert transition.intent.outcome.kind == :succeeded
    assert transition.intent.outcome.value == %{"answer" => "hello"}
    assert transition.intent.outcome.execution_id == "execution-1"
    assert execution(transition.intent).phase == :resolved
    assert execution(transition.intent).reports == [report(token)]
    assert kinds(transition) == [:report_recorded, :outcome_accepted]

    assert {:error, :intent_closed} =
             Domain.transition(transition.intent, {:create_execution, "execution-2"}, context())
  end

  test "StopOnFailure commits a known failure while RetryOnce retains evidence for later assessment" do
    for {policy, phase} <- [stop_on_failure: :closed, retry_once: :open] do
      {intent, token} = authorized(policy)

      transition =
        step(intent, {:record_report, report(token, :failure, %{"error" => "provider_error"})})

      assert transition.intent.phase == phase
      assert execution(transition.intent).phase == :resolved
      if phase == :closed, do: assert(transition.intent.outcome.kind == :failed)
    end
  end

  test "late completion after expiry is accepted independently of lease validity" do
    {intent, token} = authorized()
    unknown = step(intent, {:expire, "execution-1"}, 15).intent
    assert execution(unknown).phase == :unknown
    completed = step(unknown, {:record_report, report(token)}, 20).intent
    assert completed.outcome.kind == :succeeded
    assert execution(completed).lease.invalidated
  end

  test "Pending requires a saved completion binding and survives Worker lease expiry" do
    {intent, token} = authorized()

    assert {:error, :pending_not_supported} =
             Domain.transition(intent, {:record_report, report(token, :pending, %{})}, context())

    {intent, token} = authorized(:stop_on_failure, %{"correlation" => "approval-1"})

    waiting =
      step(intent, {:record_report, report(token, :pending, %{"approval" => "approval-1"})}).intent

    expired = step(waiting, {:expire, "execution-1"}, 15).intent
    assert execution(expired).phase == :waiting
    assert execution(expired).binding["completion"] == %{"correlation" => "approval-1"}

    assert step(
             expired,
             {:record_report, report(token, :success, %{"approved" => false}, "decision")},
             20
           ).intent.outcome.kind == :succeeded
  end

  test "late Pending restores Unknown to Waiting but cannot regress a resolved completion" do
    {intent, token} = authorized(:stop_on_failure, %{"correlation" => "approval-1"})
    unknown = step(intent, {:expire, "execution-1"}, 15).intent
    pending = report(token, :pending, %{"approval" => "approval-1"}, "pending")
    assert execution(step(unknown, {:record_report, pending}, 16).intent).phase == :waiting
    resolved = step(unknown, {:record_report, report(token)}, 16).intent
    late = step(resolved, {:record_report, pending}, 17).intent
    assert execution(late).phase == :resolved
    assert late.outcome === resolved.outcome
  end

  test "identical report retries append neither evidence nor History" do
    {intent, token} = authorized()
    completed = step(intent, {:record_report, report(token)}).intent
    duplicate = step(completed, {:record_report, report(token)}, 100)
    assert duplicate.reply == :duplicate_report
    assert duplicate.intent === completed
    assert duplicate.events == []
  end

  test "same-identity different content is preserved as conflict without replacing the projection" do
    {intent, token} = authorized(:retry_once)
    first = report(token, :failure, %{"error" => "first"})
    resolved = step(intent, {:record_report, first}).intent
    second = report(token, :success, %{"answer" => "late"})
    conflict = step(resolved, {:record_report, second})
    assert conflict.reply == :conflicting_report
    assert conflict.intent.phase == :open
    assert execution(conflict.intent).phase == :resolved
    assert execution(conflict.intent).result === first
    assert execution(conflict.intent).reports == [first, second]
    assert execution(conflict.intent).conflict
    assert kinds(conflict) == [:report_recorded, :report_conflict]
    assert step(conflict.intent, {:record_report, second}).events == []
    assert step(conflict.intent, {:cancel, "stop"}).intent.outcome.kind == :cancelled
  end

  test "different report identities with contradictory results also preserve conflict" do
    {intent, token} = authorized(:retry_once)
    first = step(intent, {:record_report, report(token, :failure, "first", "one")}).intent
    conflict = step(first, {:record_report, report(token, :failure, "second", "two")}).intent
    assert conflict.outcome == nil
    assert execution(conflict).conflict
    assert length(execution(conflict).reports) == 2
  end

  test "conflicts arriving after closure cannot replace the authoritative Outcome" do
    {intent, token} = authorized()
    first = step(intent, {:record_report, report(token)}).intent
    late = step(first, {:record_report, report(token, :failure, "error", "late")}).intent
    assert late.outcome === first.outcome
    assert execution(late).conflict
    assert execution(late).phase == :resolved
  end

  test "cancel and success preserve whichever terminal decision was applied first" do
    {intent, token} = authorized()
    success = {:record_report, report(token)}
    cancel = {:cancel, "user_request"}

    for {first, second, expected} <- [
          {success, cancel, :succeeded},
          {cancel, success, :cancelled}
        ] do
      transition = step(intent, first)
      final = step(transition.intent, second)
      assert final.intent.outcome === transition.intent.outcome
      assert final.intent.outcome.kind == expected
      refute :outcome_accepted in kinds(final)
    end
  end

  test "cancelling before any attempt does not manufacture an Execution" do
    cancelled = step(new_intent(), {:cancel, nil}).intent
    assert cancelled.outcome.kind == :cancelled
    assert cancelled.outcome.execution_id == nil
    assert cancelled.executions == %{}
  end

  test "idempotency contexts include collection scope and survive later transitions" do
    first = new_intent()
    identity = %{first.identity | collection: "collection-b"}
    assert {:ok, second} = Domain.new_intent(first.id, identity, first.definition, context())
    refute first.idempotency_context == second.intent.idempotency_context

    assert step(first, {:create_execution, "execution-1"}).intent.idempotency_context ==
             first.idempotency_context
  end

  test "two Intent snapshots isolate identical local Execution and report IDs" do
    {first, token} = authorized()
    second = new_intent(:stop_on_failure, "intent-b")
    second = step(second, {:create_execution, "execution-1"}).intent

    assert {:error, :scope_mismatch} =
             Domain.transition(second, {:record_report, report(token)}, context())

    assert step(first, {:record_report, report(token)}).intent.phase == :closed
    assert second.phase == :open
    assert execution(second).reports == []
  end

  test "unsupported recovery commands fail explicitly without creating a new attempt" do
    {intent, _token} = authorized()

    assert {:error, :unsupported_command} =
             Domain.transition(intent, {:replace_execution, "execution-2"}, context())

    assert map_size(intent.executions) == 1
  end
end
