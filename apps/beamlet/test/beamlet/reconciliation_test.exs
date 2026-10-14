defmodule Beamlet.ReconciliationTest do
  use ExUnit.Case, async: true
  alias Beamlet.{Definition, Domain, Identity, Judgment, Reconciliation, Report}
  alias Beamlet.Reconciliation.{Command, Policy}

  defp context(now \\ 0), do: %{now: now, actor: "operator"}

  defp step(intent, command, now \\ 0) do
    {:ok, transition} = Domain.transition(intent, command, context(now))
    transition
  end

  defp fixture do
    {:ok, identity} = Identity.new("collection", "agent", "key")
    {:ok, definition} = Definition.new(%{operation: "op.v1", input: nil, policy: :retry_once})
    {:ok, created} = Domain.new_intent("intent", identity, definition, context())
    intent = step(created.intent, {:create_execution, "old"}).intent
    claimed = step(intent, {:claim, "old", "worker", "session", 0, 10})
    {:claimed, token} = claimed.reply

    binding = %{
      "operation" => "op.v1",
      "handler" => "h",
      "protocol" => "p",
      "resource" => %{"account" => "a"},
      "idempotency" => %{
        "protocol" => "dedupe",
        "key" => "intent",
        "scope" => %{"account" => "a"},
        "valid_through" => nil
      }
    }

    intent = step(claimed.intent, {:authorize, token, binding}).intent
    intent = step(intent, {:expire, "old"}, 10).intent
    intent = step(intent, {:replace_execution, "old", "new", "recover"}, 10).intent
    success = %Report{id: "s", token: token, operation: "op.v1", kind: :success, body: "done"}
    intent = step(intent, {:record_report, success}, 10).intent
    {intent, success}
  end

  test "old success is adopted atomically and command replay retains its original result" do
    {intent, report} = fixture()
    assert intent.outcome == nil

    {:ok, decision} =
      Reconciliation.propose(intent, %{
        kind: :adopt_success,
        report: report,
        actor: {:operator, "operator"}
      })

    {:ok, command} = Command.new("adopt-1", decision)
    policy = %Policy{operators: ["operator"]}

    transition =
      step(intent, {:reconcile, command, policy, %{may_submit: true, may_read: true}}, 10)

    assert transition.intent.outcome.kind == :succeeded
    assert transition.intent.outcome.execution_id == "old"
    assert transition.intent.current_execution_id == "new"
    assert transition.intent.executions == intent.executions
    assert transition.intent.judgment_revision == intent.judgment_revision + 2
    assert Enum.map(transition.events, & &1.kind) == [:evidence_reconciled, :outcome_accepted]
    assert {:committed, record} = transition.reply
    assert record.result == transition.intent.outcome

    replay =
      step(
        transition.intent,
        {:reconcile, command, %Policy{}, %{may_submit: false, may_read: true}}
      )

    assert replay.reply == transition.reply
    assert replay.intent == transition.intent
    assert replay.events == []
    assert Judgment.knowledge(intent, "old") == :success
  end

  defp command(intent, report, kind, opts \\ %{}, id \\ "command") do
    {:ok, d} =
      Reconciliation.propose(
        intent,
        Map.merge(%{kind: kind, report: report, actor: {:operator, "operator"}}, opts)
      )

    {:ok, c} = Command.new(id, d)
    c
  end

  defp reconcile(
         intent,
         c,
         policy \\ %Policy{operators: ["operator"]},
         access \\ %{may_submit: true, may_read: true}
       ),
       do: step(intent, {:reconcile, c, policy, access}, 10)

  defp conflict do
    {intent, success} = fixture()
    failure = %{success | id: "f", kind: :failure, body: "error"}
    intent = step(intent, {:record_report, failure}, 10).intent
    {intent, success, failure}
  end

  defp item(report, treatment),
    do: %{
      report: report,
      treatment: treatment,
      basis: if(treatment == :keep, do: :verified_completion, else: :contract_exclusion)
    }

  defp policy(items), do: %Policy{operators: ["operator"], resolutions: [items]}

  test "full conflict coverage can adopt old success while preserving historical conflict and Knowledge" do
    {intent, success, failure} = conflict()
    items = [item(success, :keep), item(failure, :exclude)]
    c = command(intent, success, :adopt_success, %{evidence: items})
    t = reconcile(intent, c, policy(items))
    assert {:committed, _} = t.reply
    assert t.intent.outcome.value == success.body
    assert t.intent.executions == intent.executions
    assert t.intent.executions["old"].conflict
    assert length(t.intent.executions["old"].reports) == 2
  end

  test "partial coverage, unchecked resolution and contradictory retained evidence are rejected" do
    {intent, success, failure} = conflict()

    for items <- [[item(success, :keep)], [item(success, :keep), item(failure, :keep)]] do
      t =
        reconcile(
          intent,
          command(intent, success, :adopt_success, %{evidence: items}),
          policy(items)
        )

      assert {:ineligible, _} = t.reply
      assert t.intent.outcome == nil
      assert t.intent.decisions == []
      assert t.intent.judgment_revision == intent.judgment_revision
      assert t.intent.executions == intent.executions
    end

    items = [item(success, :keep), item(failure, :exclude)]

    assert {:ineligible, _} =
             reconcile(intent, command(intent, success, :adopt_success, %{evidence: items})).reply
  end

  test "all decisive evidence excluded returns unknown and retains unresolved execution risk" do
    {intent, success, failure} = conflict()
    items = [item(success, :exclude), item(failure, :exclude)]

    t =
      reconcile(
        intent,
        command(intent, success, :exclude_all_evidence, %{evidence: items}),
        policy(items)
      )

    assert {:committed, %{result: nil}} = t.reply
    assert t.intent.outcome == nil
    assert Judgment.no_conflicts?(t.intent)
    assert Judgment.knowledge(t.intent, "old") == nil
    refute Judgment.no_unresolved_risk?(t.intent)
    assert t.intent.executions["old"].result === intent.executions["old"].result
    assert t.intent.judgment_revision == intent.judgment_revision + 1
  end

  test "new evidence invalidates current disposition without deleting its ownership" do
    {intent, success, failure} = conflict()
    items = [item(success, :exclude), item(failure, :exclude)]

    t =
      reconcile(
        intent,
        command(intent, success, :exclude_all_evidence, %{evidence: items}),
        policy(items)
      )

    late = %{failure | id: "new-evidence"}
    changed = step(t.intent, {:record_report, late}).intent
    refute Judgment.no_conflicts?(changed)
    assert Judgment.applicable(changed) == []
    assert length(Judgment.bindings(changed)) == 2
    assert Judgment.knowledge(changed, "old") == :success
    all_items = items ++ [item(late, :exclude)]
    c = command(changed, success, :exclude_all_evidence, %{evidence: all_items}, "renew")
    assert [%{decision_index: 0, reports: reports}] = c.decision.supersedes
    assert Enum.sort(reports) == Enum.sort([success, failure])
    missing_ref = %{c | decision: %{c.decision | supersedes: []}}
    assert {:ineligible, _} = reconcile(changed, missing_ref, policy(all_items)).reply
    renewed = reconcile(changed, c, policy(all_items))
    assert Judgment.no_conflicts?(renewed.intent)
    assert Enum.all?(Judgment.bindings(renewed.intent), &(&1.decision_index == 1))
  end

  test "partial withdrawal removes exact ownership, does not restore older decisions or terminate" do
    {intent, success, failure} = conflict()
    items = [item(success, :exclude), item(failure, :exclude)]

    t =
      reconcile(
        intent,
        command(intent, success, :exclude_all_evidence, %{evidence: items}),
        policy(items)
      )

    refs = [%{decision_index: 0, reports: [success]}]
    c = command(t.intent, success, :withdraw_disposition, %{supersedes: refs}, "withdraw")
    p = %{policy(items) | withdrawals: [refs]}
    assert {:ineligible, _} = reconcile(t.intent, c, policy(items)).reply
    withdrawn = reconcile(t.intent, c, p)
    assert {:committed, %{result: nil}} = withdrawn.reply
    assert withdrawn.intent.outcome == nil
    assert length(Judgment.bindings(withdrawn.intent)) == 1
    assert hd(Judgment.bindings(withdrawn.intent)).item.report == failure
    refute Judgment.no_conflicts?(withdrawn.intent)
    replay = reconcile(withdrawn.intent, c, %Policy{}, %{may_submit: false, may_read: true})
    assert replay.reply == withdrawn.reply
    assert replay.intent == withdrawn.intent

    renewed =
      command(withdrawn.intent, success, :exclude_all_evidence, %{evidence: items}, "renew")

    assert renewed.decision.supersedes == [%{decision_index: 0, reports: [failure]}]
    restored = reconcile(withdrawn.intent, renewed, policy(items))
    assert Judgment.no_conflicts?(restored.intent)
    assert Enum.all?(Judgment.bindings(restored.intent), &(&1.decision_index == 2))
  end

  test "stale rejection is immutable and audit/cache changes do not advance judgment revision" do
    {intent, success} = fixture()
    c = command(intent, success, :adopt_success)
    next = step(intent, {:claim, "new", "worker", "session", 0, 10}).intent
    assert next.judgment_revision == intent.judgment_revision
    changed = step(next, {:record_report, %{success | id: "extra"}}).intent
    rejected = reconcile(changed, c)
    assert {:stale, record} = rejected.reply
    assert record.result.revision == changed.judgment_revision
    assert record.result.view == Judgment.view(changed)
    assert rejected.intent.judgment_revision == changed.judgment_revision
    assert reconcile(rejected.intent, c).reply == rejected.reply
    conflicting_id = command(rejected.intent, success, :adopt_success)

    assert {:command_identity_conflict, ^conflicting_id} =
             reconcile(rejected.intent, conflicting_id).reply
  end

  test "forbidden submissions do not consume identity; unreadable allowed submissions still commit" do
    {intent, success} = fixture()
    c = command(intent, success, :adopt_success)
    denied = reconcile(intent, c, %Policy{}, %{may_submit: true, may_read: true})
    assert denied.reply == :command_forbidden
    assert denied.intent == intent

    hidden =
      reconcile(intent, c, %Policy{operators: ["operator"]}, %{may_submit: true, may_read: false})

    assert hidden.reply == :command_forbidden
    assert hidden.intent.outcome.kind == :succeeded
    assert Map.has_key?(hidden.intent.commands, c.id)

    assert {:committed, _} =
             reconcile(hidden.intent, c, %Policy{}, %{may_submit: false, may_read: true}).reply

    assert reconcile(hidden.intent, c, %Policy{}, %{may_submit: false, may_read: false}).reply ==
             :command_forbidden
  end

  test "ineligible rejection occupies shared command identity permanently" do
    {intent, success} = fixture()
    c = command(intent, success, :exclude_from_judgment)
    rejected = reconcile(intent, c)
    assert {:ineligible, %{result: nil}} = rejected.reply

    assert reconcile(rejected.intent, c, %Policy{operators: ["operator"], excludable: [success]}).reply ==
             rejected.reply

    changed_kind = %{
      c
      | decision: %{c.decision | kind: :adopt_success, basis: :verified_completion}
    }

    assert {:command_identity_conflict, ^changed_kind} =
             reconcile(rejected.intent, changed_kind).reply
  end

  test "rule semantic versions qualify exactly and retirement preserves old nonterminal decision" do
    {intent, success} = fixture()

    rule = %{
      id: "rule",
      version: "v1",
      kinds: [:exclude_from_judgment],
      query_required: false,
      evidence_required: false
    }

    c = command(intent, success, :exclude_from_judgment, %{actor: {:rule, "rule", "v1"}})
    p = %Policy{registered_rules: [rule], excludable: [success]}
    committed = reconcile(intent, c, p)
    assert {:committed, %{result: nil}} = committed.reply
    assert Judgment.excluded?(committed.intent, success)

    assert reconcile(committed.intent, c, %Policy{}, %{may_submit: false, may_read: true}).reply ==
             committed.reply

    newer = %{rule | version: "v2", query_required: true}
    assert {:ineligible, _} = reconcile(intent, c, %{p | registered_rules: [newer]}).reply

    assert {:ineligible, _} =
             reconcile(intent, c, %{p | registered_rules: [rule, %{rule | query_required: true}]}).reply

    assert {:ineligible, _} =
             reconcile(intent, c, %{p | registered_rules: [%{rule | evidence_required: true}]}).reply

    assert Judgment.excluded?(committed.intent, success)
  end

  test "nonterminal command replay stays nonterminal after a different command closes Intent" do
    {intent, success} = fixture()
    exclude = command(intent, success, :exclude_from_judgment, %{}, "exclude")
    t = reconcile(intent, exclude, %Policy{operators: ["operator"], excludable: [success]})
    adopt = command(t.intent, success, :adopt_success, %{}, "adopt")
    closed = reconcile(t.intent, adopt)
    assert closed.intent.outcome.kind == :succeeded
    assert {:committed, %{result: nil}} = reconcile(closed.intent, exclude).reply
    assert reconcile(closed.intent, exclude).intent.outcome == closed.intent.outcome
  end

  test "Closed accepts no new coordination but replays original command records" do
    {intent, success} = fixture()
    closed = step(intent, {:cancel, "stop"}).intent
    c = command(closed, success, :adopt_success)
    t = reconcile(closed, c)
    assert {:ineligible, _} = t.reply
    assert t.intent.outcome == closed.outcome
    assert t.intent.executions == closed.executions
  end

  defp current_failure(intent) do
    claimed = step(intent, {:claim, "new", "worker", "session", 0, 10}, 10)
    {:claimed, token} = claimed.reply
    binding = intent.executions["old"].binding
    authorized = step(claimed.intent, {:authorize, token, binding}, 10).intent

    report = %Report{
      id: "current-failure",
      token: token,
      operation: "op.v1",
      kind: :failure,
      body: "failed"
    }

    {step(authorized, {:record_report, report}, 10).intent, report}
  end

  test "current Failure adoption cannot erase old success or all-excluded unresolved risk" do
    {intent, success} = fixture()
    {intent, current} = current_failure(intent)
    failure = %{success | id: "disputed", kind: :failure, body: "error"}
    intent = step(intent, {:record_report, failure}, 10).intent

    for old_items <- [
          [item(success, :keep), item(failure, :exclude)],
          [item(success, :exclude), item(failure, :exclude)]
        ] do
      items = old_items ++ [item(current, :keep)]
      cmd = command(intent, current, :adopt_failure, %{evidence: items})
      assert {:ineligible, _} = reconcile(intent, cmd, policy(items)).reply
    end

    items = [item(success, :exclude), item(failure, :keep), item(current, :keep)]
    cmd = command(intent, current, :adopt_failure, %{evidence: items})
    accepted = reconcile(intent, cmd, policy(items))
    assert {:committed, _} = accepted.reply
    assert accepted.intent.outcome.kind == :failed
    assert accepted.intent.outcome.execution_id == "new"
    assert accepted.intent.executions == intent.executions
  end

  test "ordinary failure stopping uses current interpretation while preserving original command result" do
    {intent, success} = fixture()
    {intent, current} = current_failure(intent)

    assert {:error, :unresolved_risk} =
             Domain.transition(intent, {:stop_known_failure, "new"}, context(10))

    cmd = command(intent, success, :exclude_from_judgment)
    t = reconcile(intent, cmd, %Policy{operators: ["operator"], excludable: [success]})
    stopped = step(t.intent, {:stop_known_failure, "new"}, 10)
    assert stopped.intent.outcome.kind == :failed
    assert stopped.intent.outcome.value == current.body
    assert {:committed, %{result: nil}} = reconcile(stopped.intent, cmd).reply
  end

  test "claim, renewal and non-projecting lease expiry preserve review; authorization changes it" do
    {intent, success} = fixture()
    claimed = step(intent, {:claim, "new", "worker", "session", 0, 10}, 10)
    {:claimed, token} = claimed.reply
    renewed = step(claimed.intent, {:renew, token, 20}, 10)
    assert renewed.intent.judgment_revision == intent.judgment_revision
    expired = step(renewed.intent, {:expire, "new"}, 30)
    assert expired.intent.judgment_revision == intent.judgment_revision
    cmd = command(intent, success, :adopt_success)
    assert {:committed, _} = reconcile(expired.intent, cmd).reply
    fresh = step(expired.intent, {:claim, "new", "worker", "session", 1, 10}, 30)
    {:claimed, next} = fresh.reply
    authorized = step(fresh.intent, {:authorize, next, intent.executions["old"].binding}, 30)
    assert authorized.intent.judgment_revision == intent.judgment_revision + 1
    assert {:stale, _} = reconcile(authorized.intent, cmd).reply
  end

  test "normal success advances evidence and closure judgment revisions separately" do
    {intent, _success} = fixture()
    claimed = step(intent, {:claim, "new", "worker", "session", 0, 10}, 10)
    {:claimed, token} = claimed.reply

    authorized =
      step(claimed.intent, {:authorize, token, intent.executions["old"].binding}, 10).intent

    report = %Report{
      id: "current-success",
      token: token,
      operation: "op.v1",
      kind: :success,
      body: "done"
    }

    closed = step(authorized, {:record_report, report}, 10)
    assert closed.intent.judgment_revision == authorized.judgment_revision + 2
  end

  test "extended structs or malformed report references cannot enter durable records" do
    {intent, success} = fixture()
    d = command(intent, success, :adopt_success).decision

    assert {:error, :invalid_decision} =
             Reconciliation.validate_decision(Map.put(d, :extra, true))

    assert {:error, :invalid_decision} = Reconciliation.validate_decision(%{d | report: nil})

    assert {:error, :invalid_decision} =
             Reconciliation.validate_decision(%{d | report: Map.put(success, :extra, true)})

    assert {:error, :invalid_reconciliation_policy} =
             Reconciliation.validate_policy(Map.put(%Policy{}, :extra, true))
  end

  test "proposal validation rejects duplicate reports, runtime values and malformed references" do
    {intent, success} = fixture()

    for attrs <- [
          %{kind: :bogus, report: success, actor: {:operator, "operator"}},
          %{kind: :adopt_success, report: success, actor: self()},
          %{
            kind: :adopt_success,
            report: success,
            actor: {:operator, "operator"},
            evidence: [item(success, :keep), item(success, :keep)]
          },
          %{
            kind: :withdraw_disposition,
            report: success,
            actor: {:operator, "operator"},
            supersedes: [%{decision_index: -1, reports: [success]}]
          }
        ] do
      assert {:error, :invalid_decision} = Reconciliation.propose(intent, attrs)
    end

    assert {:error, :invalid_command_id} =
             Command.new("", command(intent, success, :adopt_success).decision)

    assert {:error, :invalid_reconciliation_policy} =
             Reconciliation.validate_policy(%Policy{operators: [self()]})
  end
end
