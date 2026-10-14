defmodule Beamlet.Reconciliation do
  @moduledoc """
  Authority-qualified evidence interpretation and stable command handling.
  Proposals capture a review; handling never refreshes revision or supersessions.
  Policy/access are trusted checked local inputs, not fields of the command.
  """
  alias Beamlet.{Identity, Judgment, Outcome, Report, Transition}
  alias Beamlet.Reconciliation.{Command, Decision, Policy, Record}

  @kinds [
    :adopt_success,
    :adopt_failure,
    :exclude_from_judgment,
    :exclude_all_evidence,
    :withdraw_disposition
  ]
  @bases [:verified_completion, :contract_exclusion, :verified_withdrawal]
  @max_revision 9_223_372_036_854_775_807

  def propose(intent, attrs) when is_map(attrs) and not is_struct(attrs) do
    allowed = [:kind, :report, :actor, :evidence, :supersedes]

    if Map.keys(attrs) -- allowed == [] do
      kind = attrs[:kind]

      basis =
        cond do
          kind in [:adopt_success, :adopt_failure] -> :verified_completion
          kind == :withdraw_disposition -> :verified_withdrawal
          true -> :contract_exclusion
        end

      d =
        struct(
          Decision,
          Map.merge(attrs, %{basis: basis, reviewed_revision: intent.judgment_revision})
        )

      d =
        if Map.has_key?(attrs, :supersedes),
          do: d,
          else: %{d | supersedes: Judgment.supersessions(intent, d)}

      d = canonical(d)
      with :ok <- validate_decision(d), do: {:ok, d}
    else
      {:error, :invalid_decision}
    end
  rescue
    _error in [KeyError, BadMapError, Protocol.UndefinedError, FunctionClauseError] ->
      {:error, :invalid_decision}
  end

  def propose(_intent, _attrs), do: {:error, :invalid_decision}

  def validate_decision(%Decision{} = d) when map_size(d) == 8 do
    valid =
      d.kind in @kinds and d.basis in @bases and actor_valid?(d.actor) and
        revision_valid?(d.reviewed_revision) and valid_report?(d.report) and
        items_valid?(d.evidence) and references_valid?(d.supersedes) and d === canonical(d)

    if valid, do: :ok, else: {:error, :invalid_decision}
  end

  def validate_decision(_d), do: {:error, :invalid_decision}

  defp revision_valid?(revision), do: is_integer(revision) and revision in 0..@max_revision

  defp actor_valid?({:operator, id}), do: Identity.valid_text?(id)

  defp actor_valid?({:rule, id, version}),
    do: Identity.valid_text?(id) and Identity.valid_text?(version)

  defp actor_valid?(_actor), do: false

  defp item_valid?(%{report: r, treatment: t, basis: b} = item) when map_size(item) == 3,
    do: t in [:keep, :exclude] and b in @bases and valid_report?(r)

  defp item_valid?(_item), do: false

  defp reference_valid?(%{decision_index: index, reports: reports} = ref) when map_size(ref) == 2,
    do:
      is_integer(index) and index >= 0 and finite_set?(reports) and reports != [] and
        Enum.all?(reports, &valid_report?/1) and reports == Enum.sort(reports)

  defp reference_valid?(_ref), do: false

  defp valid_report?(%Report{} = report) do
    strict_struct?(report, Report) and strict_optional?(report.token, Beamlet.Token) and
      strict_optional?(report.source, Beamlet.Report.Source) and
      strict_optional?(report.exclusion, Beamlet.Exclusion) and
      exclusion_token_valid?(report.exclusion) and Report.validate(report) == :ok
  end

  defp valid_report?(_report), do: false
  defp strict_optional?(nil, _module), do: true
  defp strict_optional?(value, module), do: strict_struct?(value, module)

  defp strict_struct?(value, module),
    do:
      is_struct(value, module) and
        Enum.sort(Map.keys(value)) == Enum.sort(Map.keys(module.__struct__()))

  defp exclusion_token_valid?(nil), do: true

  defp exclusion_token_valid?(exclusion),
    do: strict_struct?(exclusion.authorization, Beamlet.Token)

  defp finite_set?(xs) when is_list(xs),
    do: length(xs) <= 256 and length(Enum.uniq(xs)) == length(xs)

  defp finite_set?(_xs), do: false

  defp canonical(d),
    do: %{
      d
      | evidence: Enum.sort(d.evidence),
        supersedes:
          d.supersedes |> Enum.map(&%{&1 | reports: Enum.sort(&1.reports)}) |> Enum.sort()
    }

  def process(intent, %Command{} = c, %Policy{} = policy, access, context) do
    with {:ok, ^c} <- Command.new(c.id, c.decision),
         :ok <- validate_policy(policy),
         :ok <- validate_access(access) do
      original = intent.commands[c.id]
      transition = handle(intent, c, policy, access, original, context)
      reply = visible_reply(transition, c, access)
      {:ok, %{transition | reply: reply}}
    end
  end

  def process(_intent, _command, _policy, _access, _context),
    do: {:error, :invalid_reconciliation_command}

  defp handle(intent, _c, _p, _access, %Record{} = record, _context),
    do: %Transition{intent: intent, events: [], reply: {record.status, record}}

  defp handle(intent, c, p, access, nil, context) do
    if access.may_submit and admitted?(p, c.decision.actor) do
      if eligible?(intent, p, c.decision),
        do: commit(intent, c, p, context),
        else: reject(intent, c, context)
    else
      %Transition{intent: intent, events: [], reply: :command_forbidden}
    end
  end

  defp visible_reply(_t, _c, %{may_read: false}), do: :command_forbidden

  defp visible_reply(%{reply: {_status, %{command: original}}}, c, _access) when original !== c,
    do: {:command_identity_conflict, c}

  defp visible_reply(t, _c, _access), do: t.reply

  defp admitted?(p, {:operator, id}), do: id in p.operators
  defp admitted?(p, {:rule, id, _version}), do: Enum.any?(p.registered_rules, &(&1.id == id))

  def eligible?(intent, policy, d) do
    scope_qualified?(intent, d) and actor_qualified?(policy, d) and
      contract_qualified?(policy, d) and coverage_qualified?(intent, d) and
      evidence_qualified?(intent, policy, d) and supersessions_qualified?(intent, d) and
      not duplicate_decision?(intent, d) and
      terminal_qualified?(apply_decision(intent, d, policy), d)
  end

  defp scope_qualified?(intent, d) do
    intent.phase == :open and d.reviewed_revision == intent.judgment_revision and
      d.report in Judgment.reports(intent) and source_valid?(intent, d.report) and
      (d.kind == :withdraw_disposition or
         Report.execution_id(d.report) != intent.current_execution_id or d.evidence != [])
  end

  defp source_valid?(intent, r) do
    {collection, id, e} = Report.scope(r)

    collection == intent.identity.collection and id == intent.id and
      r.operation == intent.definition.operation and Map.has_key?(intent.executions, e) and
      Report.qualified(r, intent.executions[e]) == :ok
  end

  defp actor_qualified?(p, %{actor: {:operator, id}}), do: id in p.operators

  defp actor_qualified?(p, %{actor: {:rule, id, version}} = d) do
    matches = Enum.filter(p.registered_rules, &(&1.id == id and &1.version == version))

    case matches do
      [rule] ->
        d.kind in rule.kinds and
          (not rule.query_required or Report.source_kind(d.report) == :query) and
          (not rule.evidence_required or d.evidence != [])

      _ ->
        false
    end
  end

  defp contract_qualified?(p, %{kind: :withdraw_disposition} = d),
    do: d.basis == :verified_withdrawal and set_member?(p.withdrawals, d.supersedes)

  defp contract_qualified?(_p, %{kind: :adopt_success} = d),
    do: d.report.kind == :success and d.basis == :verified_completion

  defp contract_qualified?(_p, %{kind: :adopt_failure} = d),
    do: d.report.kind == :failure and d.basis == :verified_completion

  defp contract_qualified?(_p, %{kind: :exclude_all_evidence} = d),
    do:
      d.basis == :contract_exclusion and d.evidence != [] and
        Enum.all?(d.evidence, &(&1.treatment == :exclude))

  defp contract_qualified?(p, d),
    do: d.report.kind == :success and d.basis == :contract_exclusion and d.report in p.excludable

  defp coverage_qualified?(intent, %{kind: :withdraw_disposition} = d),
    do:
      d.evidence == [] and
        Enum.all?(
          Judgment.affected(d),
          &(&1 in Judgment.reports(intent) and source_valid?(intent, &1))
        )

  defp coverage_qualified?(intent, %{evidence: []}), do: Judgment.conflict_reports(intent) == []

  defp coverage_qualified?(intent, d) do
    reports = Enum.map(d.evidence, & &1.report)
    required = Enum.uniq([d.report | Judgment.conflict_reports(intent)]) |> Enum.sort()

    Enum.sort(reports) == required and length(Enum.uniq(reports)) == length(reports) and
      Enum.all?(reports, &(&1 in Judgment.reports(intent) and source_valid?(intent, &1))) and
      Enum.any?(
        d.evidence,
        &(&1.report === d.report and
            &1.treatment == if(Judgment.terminal?(d), do: :keep, else: :exclude))
      )
  end

  defp evidence_qualified?(_intent, _p, %{kind: :withdraw_disposition} = d), do: d.evidence == []

  defp evidence_qualified?(_intent, _p, %{evidence: [], kind: kind}),
    do: kind not in [:adopt_failure, :exclude_all_evidence]

  defp evidence_qualified?(_intent, p, d) do
    kept = Enum.filter(d.evidence, &(&1.treatment == :keep))

    set_member?(p.resolutions, d.evidence) and
      Enum.all?(d.evidence, fn item ->
        item.basis ==
          if(item.treatment == :keep, do: :verified_completion, else: :contract_exclusion)
      end) and Enum.all?(kept, fn a -> Enum.all?(kept, &consistent?(a.report, &1.report)) end)
  end

  defp consistent?(a, b) do
    Report.execution_id(a) != Report.execution_id(b) or
      not ((Report.identity(a) === Report.identity(b) and a !== b) or
             (a.kind == :success and b.kind in [:failure, :not_executed]) or
             (b.kind == :success and a.kind in [:failure, :not_executed]) or
             different_result_values?(a, b))
  end

  defp different_result_values?(a, b),
    do: a.kind == b.kind and a.kind in [:success, :failure] and a.body !== b.body

  defp supersessions_qualified?(intent, d) do
    d.supersedes == Judgment.supersessions(intent, d) and
      (d.kind != :withdraw_disposition or
         (d.supersedes != [] and d.report in Judgment.affected(d) and
            Enum.all?(Judgment.affected(d), fn r ->
              Enum.any?(Judgment.applicable(intent), &(&1.item.report === r))
            end)))
  end

  defp duplicate_decision?(_intent, %{kind: :withdraw_disposition}), do: false

  defp duplicate_decision?(intent, d) do
    base = Judgment.base(intent)
    bindings = Judgment.applicable(intent)

    intent.decisions
    |> Enum.with_index()
    |> Enum.any?(fn {w, index} ->
      previous = w.decision

      w.accepted_base === base and
        Map.take(previous, [:kind, :report, :actor, :basis, :evidence]) ==
          Map.take(d, [:kind, :report, :actor, :basis, :evidence]) and
        Enum.all?(Judgment.treatments(previous), fn item ->
          Enum.any?(bindings, &(&1.decision_index == index and &1.item === item))
        end)
    end)
  end

  defp terminal_qualified?(intent, %{kind: :adopt_success}), do: Judgment.no_conflicts?(intent)

  defp terminal_qualified?(intent, %{kind: :adopt_failure, report: report}),
    do:
      Judgment.no_conflicts?(intent) and
        Report.execution_id(report) == intent.current_execution_id and
        Judgment.no_unresolved_risk?(intent) and
        not Judgment.old_success?(intent, intent.current_execution_id)

  defp terminal_qualified?(_intent, _d), do: true

  defp apply_decision(intent, d, policy) do
    witness = %{
      decision: d,
      accepted_base: Judgment.base(intent),
      accepted_revision: intent.judgment_revision,
      policy: policy
    }

    Judgment.advance(intent, %{intent | decisions: intent.decisions ++ [witness]})
  end

  defp commit(intent, c, policy, context) do
    recorded = apply_decision(intent, c.decision, policy)
    events = [event(:evidence_reconciled, c.decision, context)]
    {updated, events} = maybe_close(recorded, c.decision, events, context)

    record = %Record{
      command: c,
      status: :committed,
      result: updated.outcome,
      decision_index: length(intent.decisions)
    }

    %Transition{
      intent: %{updated | commands: Map.put(updated.commands, c.id, record)},
      events: events,
      reply: {:committed, record}
    }
  end

  defp maybe_close(intent, d, events, context) do
    if Judgment.terminal?(d) do
      outcome = Outcome.from_report(d.report)
      closed = Judgment.advance(intent, %{intent | phase: :closed, outcome: outcome})
      {closed, events ++ [event(:outcome_accepted, d, context)]}
    else
      {intent, events}
    end
  end

  defp reject(intent, c, context) do
    status =
      if c.decision.reviewed_revision == intent.judgment_revision, do: :ineligible, else: :stale

    result =
      if status == :stale, do: %{revision: intent.judgment_revision, view: Judgment.view(intent)}

    record = %Record{command: c, status: status, result: result}

    %Transition{
      intent: %{intent | commands: Map.put(intent.commands, c.id, record)},
      events: [event(:command_rejection_stored, c.decision, context)],
      reply: {status, record}
    }
  end

  defp event(kind, d, context),
    do: %{
      kind: kind,
      execution_id: Report.execution_id(d.report),
      actor: context.actor,
      at: context.now,
      version: 1,
      details: %{decision_kind: d.kind, reviewed_revision: d.reviewed_revision}
    }

  def validate_policy(%Policy{} = p) when map_size(p) == 6 do
    valid =
      valid_set?(p.operators, &Identity.valid_text?/1) and
        valid_set?(p.registered_rules, &rule_valid?/1) and
        valid_set?(p.excludable, &valid_report?/1) and
        valid_set?(p.resolutions, &items_valid?/1) and
        valid_set?(p.withdrawals, &references_valid?/1)

    if valid, do: :ok, else: {:error, :invalid_reconciliation_policy}
  end

  def validate_policy(_p), do: {:error, :invalid_reconciliation_policy}

  defp valid_set?(xs, validator), do: finite_set?(xs) and Enum.all?(xs, validator)
  defp items_valid?(xs), do: valid_set?(xs, &item_valid?/1)
  defp references_valid?(xs), do: finite_set?(xs) and Enum.all?(xs, &reference_valid?/1)
  defp set_member?(sets, items), do: Enum.any?(sets, &(Enum.sort(&1) === Enum.sort(items)))

  defp rule_valid?(
         %{id: id, version: version, kinds: kinds, query_required: q, evidence_required: e} = r
       )
       when map_size(r) == 5,
       do:
         Identity.valid_text?(id) and Identity.valid_text?(version) and finite_set?(kinds) and
           Enum.all?(kinds, &(&1 in @kinds)) and is_boolean(q) and is_boolean(e)

  defp rule_valid?(_r), do: false

  defp validate_access(%{may_submit: s, may_read: r} = a)
       when map_size(a) == 2 and is_boolean(s) and is_boolean(r), do: :ok

  defp validate_access(_access), do: {:error, :invalid_command_access}
end
