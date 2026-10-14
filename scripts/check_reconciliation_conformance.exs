# Run from apps/beamlet: mix run ../../scripts/check_reconciliation_conformance.exs
# Imports the existing Quint core guards and command processor unchanged.
defmodule BeamletReconciliationConformance do
  alias Beamlet.{Definition, Domain, Identity, Judgment, Reconciliation, Report}
  alias Beamlet.Reconciliation.{Command, Policy}
  alias Beamlet.Report.Source
  @root Path.expand("..", __DIR__)
  @context %{now: 0, actor: "1"}
  @kinds [:adopt_success, :adopt_failure, :exclude_from_judgment, :exclude_all_evidence]
  @actors [{:operator, "1"}, {:operator, "2"}, {:rule, "2", "1"}, {:rule, "2", "2"}]

  def run do
    directory =
      Path.join(
        System.tmp_dir!(),
        "beamlet-reconciliation-oracle-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    File.cp_r!(Path.join(@root, "model/quint"), Path.join(directory, "model"))
    path = Path.join(directory, "oracle.qnt")
    trace = Path.join(directory, "oracle.itf.json")
    File.write!(path, oracle())
    invoke!(["typecheck", path])

    invoke!([
      "run",
      path,
      "--main",
      "oracle",
      "--init",
      "oracleInit",
      "--step",
      "oracleStep",
      "--max-samples",
      "1",
      "--max-steps",
      "0",
      "--backend",
      "rust",
      "--n-threads",
      "1",
      "--out-itf",
      trace
    ])

    document = trace |> File.read!() |> :json.decode()
    rows = document["states"] |> List.last() |> Map.fetch!("rows") |> decode()
    Enum.each(rows, &compare!/1)
    withdrawals = document["states"] |> List.last() |> Map.fetch!("withdrawals") |> decode()
    Enum.each(withdrawals, &compare_withdrawal!/1)

    IO.puts(
      "Quint/Elixir reconciliation conformance: #{length(rows)} command and #{length(withdrawals)} withdrawal cases passed. Oracle: #{trace}"
    )
  end

  defp invoke!(args) do
    {output, status} = System.cmd("quint", args, stderr_to_stdout: true)
    if status != 0, do: raise("Quint failed: #{String.slice(output, 0, 5000)}")
  end

  defp step(intent, command, now \\ 0) do
    {:ok, t} = Domain.transition(intent, command, %{now: now, actor: "1"})
    t
  end

  defp initial(conflict) do
    {:ok, identity} = Identity.new("collection", "namespace", "key")
    {:ok, definition} = Definition.new(%{operation: "op", input: nil, policy: :retry_once})
    {:ok, t} = Domain.new_intent("intent", identity, definition, @context)
    intent = step(t.intent, {:create_execution, "1"}).intent
    claim = step(intent, {:claim, "1", "1", "1", 0, 2})
    {:claimed, t1} = claim.reply

    binding = %{
      "operation" => "op",
      "handler" => "h",
      "protocol" => "p",
      "resource" => %{},
      "query" => %{"protocol" => "q"},
      "idempotency" => %{
        "protocol" => "d",
        "key" => "intent",
        "scope" => %{"account" => "a"},
        "valid_through" => nil
      }
    }

    intent = step(claim.intent, {:authorize, t1, binding}).intent
    intent = step(intent, {:expire, "1"}, 2).intent
    intent = step(intent, {:replace_execution, "1", "2", "recover"}, 2).intent
    claim = step(intent, {:claim, "2", "2", "1", 0, 2}, 2)
    {:claimed, t2} = claim.reply
    intent = step(claim.intent, {:authorize, t2, binding}, 2).intent
    success = %Report{id: "2", token: t1, operation: "op", kind: :success, body: 0}
    failure = %Report{id: "2", token: t2, operation: "op", kind: :failure, body: 0}
    intent = step(intent, {:record_report, success}, 2).intent
    intent = step(intent, {:record_report, failure}, 2).intent

    if conflict do
      report = %Report{
        id: "3",
        operation: "op",
        kind: :failure,
        body: 0,
        source: %Source{
          kind: :query,
          collection: "collection",
          intent_id: "intent",
          execution_id: "1",
          binding: binding["query"]
        }
      }

      {step(intent, {:record_report, report}, 2).intent, success, failure}
    else
      {intent, success, failure}
    end
  end

  defp items(intent, main, mode, kind) do
    reports = Enum.uniq([main | Judgment.conflict_reports(intent)])

    chosen =
      case mode do
        0 -> []
        1 -> [main]
        _ -> reports
      end

    for r <- chosen do
      keep =
        mode != 3 or
          (kind in [:adopt_success, :adopt_failure] and (r === main or r.kind != :success)) or
          (kind == :exclude_from_judgment and r !== main)

      %{
        report: r,
        treatment: if(keep, do: :keep, else: :exclude),
        basis: if(keep, do: :verified_completion, else: :contract_exclusion)
      }
    end
  end

  defp compare!(row) do
    {intent, success, failure} = initial(row["conflict"])
    kind = Enum.at(@kinds, row["kind"])
    main = if kind == :adopt_failure, do: failure, else: success
    items = items(intent, main, row["mode"], kind)

    {:ok, d} =
      Reconciliation.propose(intent, %{
        kind: kind,
        report: main,
        actor: Enum.at(@actors, row["actor"]),
        evidence: items
      })

    d = if row["stale"], do: %{d | reviewed_revision: d.reviewed_revision - 1}, else: d
    {:ok, command} = Command.new("1", d)

    policy = %Policy{
      operators: ["1"],
      registered_rules: [
        %{
          id: "2",
          version: "1",
          kinds: [:exclude_from_judgment],
          query_required: false,
          evidence_required: false
        }
      ],
      excludable: if(row["checked"], do: [success], else: []),
      resolutions: if(row["checked"], do: [items], else: [])
    }

    access = %{may_submit: rem(row["access"], 2) == 1, may_read: row["access"] >= 2}
    eligible = Reconciliation.eligible?(intent, policy, d)
    t = step(intent, {:reconcile, command, policy, access}, 2)

    {:ok, replay} =
      Domain.transition(
        t.intent,
        {:reconcile, command, %Policy{}, %{may_submit: false, may_read: true}},
        @context
      )

    actual = %{
      "eligible" => eligible,
      "reply" => reply_kind(t.reply),
      "replay" => reply_kind(replay.reply),
      "decisions" => length(t.intent.decisions),
      "commands" => map_size(t.intent.commands),
      "revision" => t.intent.judgment_revision,
      "events" => length(t.events),
      "outcome" => if(t.intent.outcome, do: Atom.to_string(t.intent.outcome.kind), else: "none"),
      "knowledge" => knowledge(t.intent),
      "conflictsFree" => Judgment.no_conflicts?(t.intent)
    }

    expected = Map.take(row, Map.keys(actual))

    if actual != expected,
      do: raise("Reconciliation mismatch: #{inspect(row)} actual: #{inspect(actual)}")
  end

  defp compare_withdrawal!(row) do
    {intent, success, _failure} = initial(true)

    items =
      for r <- Judgment.conflict_reports(intent),
          do: %{report: r, treatment: :exclude, basis: :contract_exclusion}

    {:ok, d} =
      Reconciliation.propose(intent, %{
        kind: :exclude_all_evidence,
        report: success,
        actor: {:operator, "1"},
        evidence: items
      })

    {:ok, original} = Command.new("exclude", d)

    intent =
      step(
        intent,
        {:reconcile, original, %Policy{operators: ["1"], resolutions: [items]},
         %{may_submit: true, may_read: true}},
        2
      ).intent

    disputed = Enum.find(Judgment.reports(intent), &(&1.id == "3"))

    reports =
      case row["scope"] do
        0 -> [success]
        1 -> [disputed]
        2 -> [success, disputed]
      end

    refs =
      case row["mode"] do
        0 -> [%{decision_index: 0, reports: Enum.sort(reports)}]
        1 -> []
        2 -> [%{decision_index: 1, reports: Enum.sort(reports)}]
      end

    {:ok, d} =
      Reconciliation.propose(intent, %{
        kind: :withdraw_disposition,
        report: hd(reports),
        actor: {:operator, "1"},
        supersedes: refs
      })

    d = if row["stale"], do: %{d | reviewed_revision: d.reviewed_revision - 1}, else: d
    {:ok, c} = Command.new("withdraw", d)
    p = %Policy{operators: ["1"], withdrawals: if(row["checked"], do: [refs], else: [])}
    access = %{may_submit: rem(row["access"], 2) == 1, may_read: row["access"] >= 2}
    t = step(intent, {:reconcile, c, p, access}, 2)
    replay = step(t.intent, {:reconcile, c, %Policy{}, %{may_submit: false, may_read: true}}, 2)

    original_replay =
      step(t.intent, {:reconcile, original, %Policy{}, %{may_submit: false, may_read: true}}, 2)

    true = match?({:committed, %{result: nil}}, original_replay.reply)
    true = original_replay.intent == t.intent

    actual = %{
      "eligible" => Reconciliation.eligible?(intent, p, d),
      "reply" => reply_kind(t.reply),
      "replay" => reply_kind(replay.reply),
      "revision" => t.intent.judgment_revision,
      "bindings" => length(Judgment.bindings(t.intent)),
      "knowledge" => knowledge(t.intent),
      "conflictsFree" => Judgment.no_conflicts?(t.intent),
      "events" => length(t.events)
    }

    if actual != Map.take(row, Map.keys(actual)),
      do: raise("Withdrawal mismatch: #{inspect(row)} actual: #{inspect(actual)}")
  end

  defp knowledge(intent),
    do:
      if(Judgment.knowledge(intent, "1"),
        do: Atom.to_string(Judgment.knowledge(intent, "1")),
        else: "none"
      )

  defp reply_kind(:command_forbidden), do: "forbidden"
  defp reply_kind({status, _}), do: Atom.to_string(status)
  defp decode(%{"#bigint" => value}), do: String.to_integer(value)
  defp decode(%{"#list" => values}), do: Enum.map(values, &decode/1)
  defp decode(value) when is_map(value), do: Map.new(value, fn {k, v} -> {k, decode(v)} end)
  defp decode(value) when is_list(value), do: Enum.map(value, &decode/1)
  defp decode(value), do: value

  defp oracle do
    """
    module oracle {
      import beamletCore(WORKERS=Set(1,2), EXECUTIONS=Set(1,2), REPORT_IDS=Set(1,2,3,4),
        CLOCK_VALUES=0.to(6), MAX_INCARNATION=2, MAX_GENERATION=3, TTL=2,
        ALLOW_REPEAT=true, CAN_FENCE=false).* from "./model/beamletCore"
      pure val t1: Token = {exec:1,worker:1,incarnation:1,generation:1}
      pure val t2: Token = {exec:2,worker:2,incarnation:1,generation:1}
      pure val success: Report = {id:2,exec:1,kind:Success,value:0,origin:ByWorker(t1)}
      pure val failure: Report = {id:2,exec:2,kind:Failure,value:0,origin:ByWorker(t2)}
      pure val disputed: Report = {id:3,exec:1,kind:Failure,value:0,origin:ByQuery}
      pure val l1 = applyAuthorize(applyClaim(applyCreate(initialLedger,1),1,1,1,0),t1,0)
      pure val l2 = applyReplace(applyExpire(l1,1),1,2)
      pure val l3 = applyAuthorize(applyClaim(l2,2,2,1,2),t2,2)
      pure val ready = applyReport(applyReport(l3,success),failure)
      pure val kinds = List(AdoptSuccess,AdoptFailure,ExcludeFromJudgment,ExcludeAllEvidence)
      pure val actors = List(Operator(1),Operator(2),AutomaticRule({id:2,version:1}),AutomaticRule({id:2,version:2}))
      pure def replyKind(r: CommandReply): str = match r {
        | CommandCommitted(_) => "committed" | CommandStale(_) => "stale"
        | CommandIneligible(_) => "ineligible" | CommandForbidden(_) => "forbidden"
        | CommandIdentityConflict(_) => "command_identity_conflict"
      }
      type Row = {conflict:bool,kind:int,mode:int,actor:int,checked:bool,stale:bool,access:int,
        eligible:bool,reply:str,replay:str,decisions:int,commands:int,revision:int,events:int,
        outcome:str,knowledge:str,conflictsFree:bool}
      pure def row(conflict: bool, kind: int, mode: int, actor: int, checked: bool, stale: bool, access: int): Row = {
        val l = if(conflict) applyReport(ready,disputed) else ready
        val k = kinds.nth(kind)
        val main = if(k == AdoptFailure) failure else success
        val required = conflictReports(l).union(Set(main))
        val chosen = if(mode == 0) Set() else if(mode == 1) Set(main) else required
        val items = chosen.map(r => {
          val keep = mode != 3 or ((k == AdoptSuccess or k == AdoptFailure) and (r == main or r.kind != Success))
            or (k == ExcludeFromJudgment and r != main)
          {report:r,treatment:if(keep) KeepEvidence else ExcludeEvidence,
            basis:if(keep) VerifiedCompletion else ContractExclusion}
        })
        val d0 = proposeDecision(l,main,k,actors.nth(actor))
        val d = withSupersessions(l,{...d0,evidence:items,reviewedRevision: l.revision - (if(stale) 1 else 0)})
        val p: ReconciliationPolicy = {operators:Set(1),registeredRules:Set(rule2v1),
          excludable:if(checked) Set(success) else Set(),resolutions:if(checked) Set(items) else Set(),withdrawals:Set()}
        val c: ReconciliationCommand = {id:1,decision:d}
        val a: CommandAccess = {maySubmit:access % 2 == 1,mayRead:access >= 2}
        val updated = processCommand(l,p,c,a)
        val empty: ReconciliationPolicy = {operators:Set(),registeredRules:Set(),excludable:Set(),resolutions:Set(),withdrawals:Set()}
        val reply = commandReplyWithAccess(l,p,c,a)
        val replay = commandReplyWithAccess(updated,empty,c,{maySubmit:false,mayRead:true})
        val known = judgmentKnowledge(updated,1)
        {conflict:conflict,kind:kind,mode:mode,actor:actor,checked:checked,stale:stale,access:access,
          eligible:canReconcile(l,p,d),reply:replyKind(reply),replay:replyKind(replay),
          decisions:updated.decisions.length(),commands:updated.commands.length()+updated.rejections.length(),
          revision:updated.revision,events:updated.history.length()-l.history.length(),
          outcome:if(updated.outcomes.length() == 0) "none" else if(updated.outcomes.head().kind == OutcomeSucceeded) "succeeded" else "failed",
          knowledge:if(known == SuccessKnown) "success" else if(known == FailureKnown) "failure" else if(known == NotExecutedKnown) "not_executed" else "none",
          conflictsFree:noConflicts(updated)}
      }
      type WithdrawalRow = {scope:int,mode:int,checked:bool,stale:bool,access:int,
        eligible:bool,reply:str,replay:str,revision:int,bindings:int,knowledge:str,conflictsFree:bool,events:int}
      pure def withdrawalRow(scope:int,mode:int,checked:bool,stale:bool,access:int): WithdrawalRow = {
        val l0 = applyReport(ready,disputed)
        val items = conflictReports(l0).map(r => {report:r,treatment:ExcludeEvidence,basis:ContractExclusion})
        val initial = withSupersessions(l0,{...proposeDecision(l0,success,ExcludeAllEvidence,Operator(1)),evidence:items})
        val initialPolicy: ReconciliationPolicy = {operators:Set(1),registeredRules:Set(),excludable:Set(),resolutions:Set(items),withdrawals:Set()}
        val l = applyReconcileAndMaybeCommit(l0,initialPolicy,initial)
        val rs = if(scope == 0) Set(success) else if(scope == 1) Set(disputed) else Set(success,disputed)
        val refs: Set[Supersession] = if(mode == 1) Set() else Set({decisionIndex:if(mode == 2) 1 else 0,reports:rs})
        val d: Decision = {...proposeDecision(l,if(scope == 1) disputed else success,WithdrawDisposition,Operator(1)),
          basis:VerifiedWithdrawal,supersedes:refs,reviewedRevision:l.revision-(if(stale) 1 else 0)}
        val p: ReconciliationPolicy = {operators:Set(1),registeredRules:Set(),excludable:Set(),resolutions:Set(),withdrawals:if(checked) Set(refs) else Set()}
        val c: ReconciliationCommand = {id:1,decision:d}
        val a: CommandAccess = {maySubmit:access % 2 == 1,mayRead:access >= 2}
        val updated = processCommand(l,p,c,a)
        val empty: ReconciliationPolicy = {operators:Set(),registeredRules:Set(),excludable:Set(),resolutions:Set(),withdrawals:Set()}
        val known = judgmentKnowledge(updated,1)
        {scope:scope,mode:mode,checked:checked,stale:stale,access:access,eligible:canReconcile(l,p,d),
          reply:replyKind(commandReplyWithAccess(l,p,c,a)),
          replay:replyKind(commandReplyWithAccess(updated,empty,c,{maySubmit:false,mayRead:true})),
          revision:updated.revision,bindings:historicalBindings(updated.decisions).size(),
          knowledge:if(known == SuccessKnown) "success" else "none",
          conflictsFree:noConflicts(updated),events:updated.history.length()-l.history.length()}
      }
      var withdrawals: List[WithdrawalRow]
      var rows: List[Row]
      action oracleInit = all {init,
        withdrawals'=0.to(2).fold(List(),(xs,scope) => xs.concat(0.to(2).fold(List(),(ys,mode) =>
          ys.concat(0.to(3).fold(List(),(zs,access) => zs.concat(Set(false,true).fold(List(),(cs,checked) =>
            cs.concat(Set(false,true).fold(List(),(ss,stale) => ss.append(withdrawalRow(scope,mode,checked,stale,access))))))))))),
        rows' = 0.to(3).fold(List(), (xs,k) => xs.concat(
        0.to(3).fold(List(), (ys,m) => ys.concat(0.to(3).fold(List(), (zs,a) => zs.concat(
          0.to(3).fold(List(), (rs,access) => rs.concat(Set(false,true).fold(List(),(cs,conflict) =>
            cs.concat(Set(false,true).fold(List(),(ps,checked) => ps.concat(Set(false,true).fold(List(),(ss,stale) =>
              ss.append(row(conflict,k,m,a,checked,stale,access))))))))))))))) }
      action oracleStep = all {authority'=authority,workers'=workers,network'=network,external'=external,clock'=clock,rows'=rows,withdrawals'=withdrawals}
    }
    """
  end
end

BeamletReconciliationConformance.run()
