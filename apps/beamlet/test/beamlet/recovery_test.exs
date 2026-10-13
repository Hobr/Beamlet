defmodule Beamlet.RecoveryTest do
  use ExUnit.Case, async: true
  import Kernel, except: [binding: 0, binding: 1]

  alias Beamlet.{Definition, Domain, Exclusion, Identity, Report, Transition}
  alias Beamlet.Report.Source

  defp context(now \\ 10, contract_time \\ 100),
    do: %{now: now, actor: "authority-a", contract_time: contract_time}

  defp step(intent, command, context \\ context()) do
    assert {:ok, %Transition{} = transition} = Domain.transition(intent, command, context)
    assert transition.intent.phase == :closed == (transition.intent.outcome != nil)
    assert map_size(transition.intent.executions) <= 2
    if intent.outcome, do: assert(transition.intent.outcome === intent.outcome)
    transition
  end

  defp prepared(policy \\ :retry_once) do
    {:ok, definition} = Definition.new(%{operation: "request.v1", input: nil, policy: policy})
    {:ok, identity} = Identity.new("collection-a", "agent-a", "call-a")
    {:ok, created} = Domain.new_intent("intent-a", identity, definition, context())
    step(created.intent, {:create_execution, "execution-1"}).intent
  end

  defp binding(capability \\ :unbounded) do
    binding = %{
      "operation" => "request.v1",
      "handler" => "handler.v1",
      "protocol" => "invoke.v1",
      "resource" => %{"provider" => "provider-a", "account" => "account-a"},
      "completion" => %{
        "protocol" => "callback.v1",
        "provider" => "provider-a",
        "account" => "account-a",
        "correlation" => "job-a"
      },
      "query" => %{
        "protocol" => "query.v1",
        "provider" => "provider-a",
        "account" => "account-a",
        "correlation" => "job-a"
      }
    }

    contract = %{
      "protocol" => "dedupe.v1",
      "scope" => %{"account" => "account-a"},
      "key" => "intent-a-key",
      "valid_through" => nil
    }

    case capability do
      :none ->
        binding

      :unbounded ->
        Map.put(binding, "idempotency", contract)

      expiry when is_integer(expiry) ->
        Map.put(
          binding,
          "idempotency",
          %{contract | "valid_through" => expiry} |> Map.put("expiry_enforced", true)
        )
    end
  end

  defp claim(intent, id \\ "execution-1") do
    transition = step(intent, {:claim, id, "worker-a", "session-a", 0, 5})
    {:claimed, token} = transition.reply
    {transition.intent, token}
  end

  defp authorized(capability \\ :unbounded, policy \\ :retry_once) do
    {intent, token} = claim(prepared(policy))
    {step(intent, {:authorize, token, binding(capability)}).intent, token}
  end

  defp worker_report(token, kind, body \\ nil, id \\ "worker-report"),
    do: %Report{id: id, token: token, operation: "request.v1", kind: kind, body: body}

  defp external_report(token, source_kind, kind, handler_binding, body \\ nil) do
    key = if source_kind == :callback, do: "completion", else: "query"

    source = %Source{
      kind: source_kind,
      collection: token.collection,
      intent_id: token.intent_id,
      execution_id: token.execution_id,
      binding: handler_binding[key]
    }

    %Report{
      id: "external-report",
      source: source,
      operation: "request.v1",
      kind: kind,
      body: body
    }
  end

  defp exclusion_report(token, handler_binding) do
    report = external_report(token, :query, :not_executed, handler_binding)

    %{
      report
      | exclusion: %Exclusion{
          authorization: token,
          query_binding: handler_binding["query"],
          evidence_ref: "fence-receipt-a"
        }
    }
  end

  defp unknown(capability \\ :unbounded) do
    {intent, token} = authorized(capability)
    {step(intent, {:expire, token.execution_id}, context(15)).intent, token}
  end

  defp replace(intent, context \\ context()),
    do: step(intent, {:replace_execution, "execution-1", "execution-2", "recover"}, context)

  defp retry_authorized(intent, capability \\ :unbounded) do
    {intent, token} = claim(replace(intent).intent, "execution-2")
    {step(intent, {:authorize, token, binding(capability)}).intent, token}
  end

  test "unstarted replacement preserves intent definition and invalidates a live old lease" do
    {intent, old_token} = claim(prepared())
    transition = replace(intent)
    assert transition.reply == {:replaced, "execution-2", :unstarted}
    assert transition.intent.definition === intent.definition
    assert transition.intent.idempotency_context === intent.idempotency_context
    assert transition.intent.executions["execution-1"].lease.invalidated
    assert transition.intent.executions["execution-1"].authorization == nil

    assert [
             %{
               kind: :execution_replaced,
               details: %{basis: :unstarted, from_execution_id: "execution-1", old_generation: 1}
             }
           ] = transition.events

    assert {:error, :not_current_execution} =
             Domain.transition(transition.intent, {:authorize, old_token, binding()}, context())

    {fresh, new_token} = claim(transition.intent, "execution-2")
    assert new_token.generation == 1

    assert step(fresh, {:authorize, new_token, binding(:none)}).intent.executions["execution-2"].authorization ==
             new_token
  end

  test "creation counts against RetryOnce even when neither attempt was invoked" do
    transition = replace(prepared())
    assert transition.intent.executions["execution-1"].lease == nil

    assert {:error, :retry_budget_exhausted} =
             Domain.transition(
               transition.intent,
               {:replace_execution, "execution-2", "execution-3", "recover"},
               context()
             )

    assert {:error, :retry_disabled} =
             Domain.transition(
               prepared(:stop_on_failure),
               {:replace_execution, "execution-1", "execution-2", "recover"},
               context()
             )
  end

  test "replacement replay returns the original result without history, including after closure" do
    transition = replace(prepared())
    closed = step(transition.intent, {:cancel, "cancelled"}).intent
    replay = replace(closed)
    assert replay.reply == {:existing_execution, "execution-2"}
    assert replay.intent === closed
    assert replay.events == []

    assert {:error, :execution_id_reused} =
             Domain.transition(
               closed,
               {:replace_execution, "execution-1", "execution-2", "different reason"},
               context()
             )

    assert {:error, :invalid_replacement} =
             Domain.transition(
               prepared(),
               {:replace_execution, "execution-1", "execution-2", ""},
               context()
             )
  end

  test "Unknown without an external guarantee cannot be replaced" do
    {intent, _token} = unknown(:none)

    assert {:error, :unsafe_retry} =
             Domain.transition(
               intent,
               {:replace_execution, "execution-1", "execution-2", "timeout"},
               context()
             )

    assert {:error, :known_failure_required} =
             Domain.transition(intent, {:stop_known_failure, "execution-1"}, context())
  end

  test "a known failure alone is not a safe retry basis and RetryOnce may stop on its first error" do
    {intent, token} = authorized(:none)

    transition =
      step(
        intent,
        {:record_report, worker_report(token, :failure, %{"partial_effects_possible" => true})}
      )

    assert transition.intent.outcome.kind == :failed
    assert map_size(transition.intent.executions) == 1
  end

  test "a known failure with an unbounded original idempotency protocol remains retryable" do
    {intent, token} = authorized()
    failed = step(intent, {:record_report, worker_report(token, :failure)}).intent
    assert failed.phase == :open

    assert {:error, :retry_available} =
             Domain.transition(failed, {:stop_known_failure, "execution-1"}, context())

    assert replace(failed).reply == {:replaced, "execution-2", :idempotency}
  end

  test "Pending does not permit blind replacement even with idempotency or an expired lease" do
    {intent, token} = authorized()
    pending = step(intent, {:record_report, worker_report(token, :pending)}).intent
    expired = step(pending, {:expire, "execution-1"}, context(15)).intent
    assert expired.executions["execution-1"].phase == :waiting

    assert {:error, :no_recovery_reason} =
             Domain.transition(
               expired,
               {:replace_execution, "execution-1", "execution-2", "timeout"},
               context()
             )
  end

  test "NotFound is retained as evidence and never turns Unknown into a safe retry or failure" do
    {intent, token} = unknown(:none)
    report = external_report(token, :query, :not_found, binding(:none))
    transition = step(intent, {:record_report, report})
    execution = transition.intent.executions["execution-1"]
    assert execution.phase == :unknown
    assert execution.result == nil
    assert execution.reports == [report]
    assert step(transition.intent, {:record_report, report}).events == []

    assert {:error, :unsafe_retry} =
             Domain.transition(
               transition.intent,
               {:replace_execution, "execution-1", "execution-2", "not found"},
               context()
             )

    assert {:error, :known_failure_required} =
             Domain.transition(transition.intent, {:stop_known_failure, "execution-1"}, context())
  end

  test "verified NotExecuted excludes an authorized attempt without requiring idempotency" do
    {intent, token} = authorized(:none)
    pending = step(intent, {:record_report, worker_report(token, :pending)}).intent
    report = exclusion_report(token, binding(:none))
    resolved = step(pending, {:record_report, report}).intent
    assert resolved.phase == :open
    assert resolved.executions["execution-1"].exclusion === report.exclusion
    assert resolved.executions["execution-1"].phase == :resolved
    assert replace(resolved).reply == {:replaced, "execution-2", :not_executed}
  end

  test "NotExecuted requires trusted exclusion metadata, not flags in a query body" do
    {intent, token} = unknown(:none)

    report =
      external_report(token, :query, :not_executed, binding(:none), %{
        "excludes_past" => true,
        "excludes_future" => true
      })

    assert {:error, :missing_exclusion} =
             Domain.transition(intent, {:record_report, report}, context())

    verified = exclusion_report(token, binding(:none))

    wrong = %{
      verified
      | exclusion: %{verified.exclusion | authorization: %{token | generation: 2}}
    }

    assert {:error, :exclusion_mismatch} =
             Domain.transition(intent, {:record_report, wrong}, context())

    wrong = %{
      verified
      | exclusion: %{verified.exclusion | query_binding: %{"protocol" => "other.v1"}}
    }

    assert {:error, :invalid_exclusion} =
             Domain.transition(intent, {:record_report, wrong}, context())

    wrong = %{verified | exclusion: %{verified.exclusion | evidence_ref: ""}}

    assert {:error, :invalid_exclusion} =
             Domain.transition(intent, {:record_report, wrong}, context())
  end

  test "late Success conflicts with NotExecuted and blocks replacement" do
    {intent, token} = unknown(:none)
    excluded = step(intent, {:record_report, exclusion_report(token, binding(:none))}).intent
    transition = step(excluded, {:record_report, worker_report(token, :success)})
    execution = transition.intent.executions["execution-1"]
    assert execution.conflict
    assert execution.result.kind == :not_executed
    assert length(execution.reports) == 2
    assert transition.intent.outcome == nil

    assert {:error, :unreconciled_conflict} =
             Domain.transition(
               transition.intent,
               {:replace_execution, "execution-1", "execution-2", "recover"},
               context()
             )
  end

  test "NotExecuted after accepted Success preserves Outcome while recording the contradiction" do
    {intent, token} = authorized(:none)
    success = step(intent, {:record_report, worker_report(token, :success)}).intent
    transition = step(success, {:record_report, exclusion_report(token, binding(:none))})
    assert transition.intent.outcome === success.outcome
    assert transition.intent.executions["execution-1"].exclusion == nil
    assert transition.intent.executions["execution-1"].conflict
  end

  test "finite retry windows use contract time, including their boundary, independently of lease time" do
    {intent, _token} = unknown(100)
    assert replace(intent, context(-1000, 100)).reply == {:replaced, "execution-2", :idempotency}

    assert {:error, :unsafe_retry} =
             Domain.transition(
               intent,
               {:replace_execution, "execution-1", "execution-2", "recover"},
               context(-1000, 101)
             )

    assert {:error, :unsafe_retry} =
             Domain.transition(
               intent,
               {:replace_execution, "execution-1", "execution-2", "recover"},
               %{now: 10, actor: "authority-a"}
             )

    assert {:error, :invalid_context} =
             Domain.transition(
               intent,
               {:replace_execution, "execution-1", "execution-2", "recover"},
               context(10, -1)
             )
  end

  test "a finite provider cache without enforced expiry is not a safe retry protocol" do
    {intent, token} = claim(prepared())
    unsafe = put_in(binding(200), ["idempotency", "expiry_enforced"], false)
    intent = step(intent, {:authorize, token, unsafe}).intent
    intent = step(intent, {:expire, "execution-1"}, context(15)).intent

    assert {:error, :unsafe_retry} =
             Domain.transition(
               intent,
               {:replace_execution, "execution-1", "execution-2", "recover"},
               context()
             )
  end

  test "replacement before expiry does not grant authorization after the original window expires" do
    {intent, _old_token} = unknown(100)
    {intent, token} = claim(replace(intent).intent, "execution-2")

    assert {:error, :idempotency_contract_unavailable} =
             Domain.transition(intent, {:authorize, token, binding(200)}, context(11, 101))

    assert intent.executions["execution-2"].authorization == nil
  end

  test "retry authorization preserves original resource, protocol, key and scope" do
    {intent, _old_token} = unknown()
    {intent, token} = claim(replace(intent).intent, "execution-2")

    variants = [
      {put_in(binding(), ["resource", "account"], "other"), :retry_resource_mismatch},
      {put_in(binding(), ["protocol"], "other.v1"), :idempotency_contract_unavailable},
      {put_in(binding(), ["idempotency", "protocol"], "other.v1"),
       :idempotency_contract_unavailable},
      {put_in(binding(), ["idempotency", "key"], "different"), :idempotency_contract_unavailable},
      {put_in(binding(), ["idempotency", "scope", "account"], "different"),
       :idempotency_contract_unavailable}
    ]

    for {changed, reason} <- variants do
      assert {:error, ^reason} =
               Domain.transition(intent, {:authorize, token, changed}, context())
    end
  end

  test "a retry grant is checked again before invocation; replay cannot extend its contract" do
    {intent, _old_token} = unknown(100)
    {intent, token} = retry_authorized(intent, 100)
    assert :ok = Domain.check_invocation(intent, token, context(11, 100))

    assert {:error, :idempotency_contract_unavailable} =
             Domain.check_invocation(intent, token, context(-1000, 101))

    replay = step(intent, {:authorize, token, binding(999)}, context(12, 101))
    assert replay.events == []
    assert replay.intent === intent
    assert {:authorized, ^token, original} = replay.reply
    assert original["idempotency"]["valid_through"] == 100
  end

  test "invocation check rejects ungranted tokens and does not treat cancellation as external stopping" do
    {intent, token} = claim(prepared())
    assert {:error, :unauthorized_invocation} = Domain.check_invocation(intent, token, context())
    intent = step(intent, {:authorize, token, binding()}).intent
    intent = step(intent, {:cancel, "cancelled"}).intent
    assert :ok = Domain.check_invocation(intent, token, context())

    assert {:error, :scope_mismatch} =
             Domain.check_invocation(intent, %{token | collection: "other"}, context())
  end

  test "two known failures exhaust RetryOnce and accept only the current attempt's failure" do
    {intent, old_token} = authorized()
    first = step(intent, {:record_report, worker_report(old_token, :failure, "first")}).intent
    {intent, token} = retry_authorized(first)
    transition = step(intent, {:record_report, worker_report(token, :failure, "second")})
    assert transition.intent.outcome.kind == :failed
    assert transition.intent.outcome.execution_id == "execution-2"
    assert transition.intent.outcome.value == "second"
  end

  test "budget exhaustion cannot hide an unresolved old attempt; explicit stopping works after late failure" do
    {intent, old_token} = unknown()
    {intent, token} = retry_authorized(intent)
    failed = step(intent, {:record_report, worker_report(token, :failure, "current")}).intent
    assert failed.phase == :open

    assert {:error, :unresolved_risk} =
             Domain.transition(failed, {:stop_known_failure, "execution-2"}, context())

    resolved = step(failed, {:record_report, worker_report(old_token, :failure, "old")}).intent
    assert resolved.phase == :open
    stopped = step(resolved, {:stop_known_failure, "execution-2"})
    assert stopped.intent.outcome.value == "current"
    assert stopped.intent.outcome.execution_id == "execution-2"
  end

  test "an old Success is evidence, never a qualified current Outcome or a basis to accept current failure" do
    {intent, old_token} = unknown()
    {intent, token} = retry_authorized(intent)
    success = step(intent, {:record_report, worker_report(old_token, :success, "old")}).intent
    assert success.phase == :open
    failed = step(success, {:record_report, worker_report(token, :failure, "current")}).intent
    assert failed.outcome == nil

    assert {:error, :unresolved_risk} =
             Domain.transition(failed, {:stop_known_failure, "execution-2"}, context())
  end

  test "current Success can settle the intent while an older attempt remains Unknown" do
    {intent, old_token} = unknown()
    {intent, token} = retry_authorized(intent)
    success = step(intent, {:record_report, worker_report(token, :success)}).intent
    assert success.outcome.kind == :succeeded
    assert success.outcome.execution_id == token.execution_id
    assert success.executions[old_token.execution_id].phase == :unknown
  end

  test "a saved known failure can be stopped after a finite retry window expires" do
    {intent, token} = authorized(100)
    failed = step(intent, {:record_report, worker_report(token, :failure)}).intent
    assert failed.phase == :open
    stopped = step(failed, {:stop_known_failure, "execution-1"}, context(11, 101))
    assert stopped.intent.outcome.kind == :failed
    assert [%{details: %{reason: :stop_known_failure}}] = stopped.events
    replay = step(stopped.intent, {:stop_known_failure, "execution-1"})
    assert replay.events == []
    assert replay.intent === stopped.intent
  end

  test "a conflict cannot be overridden by retry safety or policy stopping" do
    {intent, token} = authorized(100)
    failure = step(intent, {:record_report, worker_report(token, :failure)}).intent

    conflict =
      step(failure, {:record_report, worker_report(token, :success, nil, "other")}).intent

    assert {:error, :unreconciled_conflict} =
             Domain.transition(
               conflict,
               {:replace_execution, "execution-1", "execution-2", "recover"},
               context()
             )

    assert {:error, :unresolved_risk} =
             Domain.transition(conflict, {:stop_known_failure, "execution-1"}, context(11, 101))
  end

  test "authenticated callback Success can complete Unknown after the Worker disappears" do
    {intent, token} = unknown(:none)
    report = external_report(token, :callback, :success, binding(:none), "answer")
    assert report.token == nil
    transition = step(intent, {:record_report, report})
    assert transition.intent.outcome.kind == :succeeded
    assert transition.intent.outcome.report_identity == Report.identity(report)
    assert transition.intent.outcome.value == "answer"
  end

  test "query Success can complete Pending after lease expiry" do
    {intent, token} = authorized(:none)
    pending = step(intent, {:record_report, worker_report(token, :pending)}).intent
    expired = step(pending, {:expire, "execution-1"}, context(15)).intent
    report = external_report(token, :query, :success, binding(:none))
    transition = step(expired, {:record_report, report})
    assert transition.intent.outcome.kind == :succeeded
    assert transition.intent.executions["execution-1"].lease.invalidated
  end

  test "callback scope and original account/correlation/protocol are checked before evidence is retained" do
    {intent, token} = authorized(:none)
    report = external_report(token, :callback, :success, binding(:none))

    variants = [
      {%{report.source | collection: "other"}, :scope_mismatch},
      {%{report.source | intent_id: "other"}, :scope_mismatch},
      {%{report.source | execution_id: "other"}, :execution_not_found},
      {%{report.source | binding: Map.put(report.source.binding, "account", "other")},
       :source_binding_mismatch},
      {%{report.source | binding: Map.put(report.source.binding, "correlation", "other")},
       :source_binding_mismatch},
      {%{report.source | binding: Map.put(report.source.binding, "protocol", "other.v1")},
       :source_binding_mismatch}
    ]

    for {source, reason} <- variants do
      assert {:error, ^reason} =
               Domain.transition(intent, {:record_report, %{report | source: source}}, context())
    end

    assert intent.executions["execution-1"].reports == []
  end

  test "ambiguous sources and inappropriate evidence kinds cannot enter the domain" do
    {intent, token} = authorized(:none)
    report = external_report(token, :callback, :success, binding(:none))

    assert {:error, :invalid_report_source} =
             Domain.transition(intent, {:record_report, %{report | token: token}}, context())

    for source <- [:callback, :query] do
      pending = external_report(token, source, :pending, binding(:none))

      assert {:error, :unsupported_report_kind} =
               Domain.transition(intent, {:record_report, pending}, context())
    end

    assert {:error, :unsupported_report_kind} =
             Domain.transition(
               intent,
               {:record_report, worker_report(token, :not_found)},
               context()
             )

    assert {:error, :unauthorized_report} =
             Domain.transition(prepared(), {:record_report, report}, context())
  end

  test "callback duplicate and contradiction preserve the first accepted immutable Outcome" do
    {intent, token} = authorized(:none)
    report = external_report(token, :callback, :success, binding(:none), "first")
    success = step(intent, {:record_report, report}).intent
    duplicate = step(success, {:record_report, report})
    assert duplicate.events == []
    assert duplicate.intent === success
    contradictory = step(success, {:record_report, %{report | body: "second"}}).intent
    assert contradictory.outcome === success.outcome
    assert contradictory.executions["execution-1"].conflict
    assert length(contradictory.executions["execution-1"].reports) == 2
  end

  test "lease expiry still commits its barrier when the retry contract has also expired" do
    {intent, _old_token} = unknown(100)
    {intent, token} = claim(replace(intent).intent, "execution-2")
    rejected = step(intent, {:authorize, token, binding(200)}, context(15, 101))
    assert rejected.reply == {:rejected, :lease_expired}
    assert [%{kind: :lease_expired}] = rejected.events
    assert rejected.intent.executions["execution-2"].lease.invalidated

    assert {:error, :lease_expired} =
             Domain.transition(
               rejected.intent,
               {:authorize, token, binding(100)},
               context(10, 100)
             )
  end

  test "missing idempotency window metadata cannot silently become an unbounded guarantee" do
    {intent, token} = claim(prepared())
    malformed = Map.update!(binding(), "idempotency", &Map.delete(&1, "valid_through"))

    assert {:error, :invalid_idempotency_contract} =
             Domain.transition(intent, {:authorize, token, malformed}, context())

    malformed = put_in(binding(), ["completion"], %{})

    assert {:error, :invalid_handler_binding} =
             Domain.transition(intent, {:authorize, token, malformed}, context())
  end

  test "query and callback reports share conflict rules without sharing report identities" do
    {intent, token} = authorized()
    query = external_report(token, :query, :failure, binding(), "failed")
    callback = external_report(token, :callback, :success, binding(), "succeeded")
    assert Report.identity(query) != Report.identity(callback)
    failed = step(intent, {:record_report, query}).intent
    contradictory = step(failed, {:record_report, callback}).intent
    assert contradictory.phase == :open
    assert contradictory.executions["execution-1"].result === query
    assert contradictory.executions["execution-1"].conflict
  end
end
