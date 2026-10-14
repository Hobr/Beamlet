defmodule Beamlet.Judgment do
  @moduledoc """
  Pure current interpretation of immutable execution evidence.
  Historical conflict flags and original Knowledge remain unchanged. Dispositions
  apply only to their accepted base; new evidence invalidates applicability but
  preserves ownership links. Lease controls, command caches and rejection audit
  do not change this base or its independent revision.
  """
  alias Beamlet.Report

  def reports(intent),
    do: intent.executions |> Enum.flat_map(fn {_id, e} -> e.reports end) |> Enum.sort()

  def base(intent) do
    attempts =
      Map.new(intent.executions, fn {id, e} ->
        {id,
         %{
           phase: e.phase,
           authorization: e.authorization,
           knowledge: if(e.result, do: e.result.kind),
           conflict: e.conflict
         }}
      end)

    %{
      phase: intent.phase,
      current_execution_id: intent.current_execution_id,
      reports: reports(intent),
      attempts: attempts
    }
  end

  def view(intent),
    do: %{base: base(intent), decisions: Enum.map(intent.decisions, & &1.decision)}

  def advance(before, after_intent) do
    if view(before) === view(after_intent),
      do: after_intent,
      else: %{after_intent | judgment_revision: before.judgment_revision + 1}
  end

  def treatments(%{kind: :withdraw_disposition}), do: []
  def treatments(%{evidence: [_ | _] = items}), do: items

  def treatments(d),
    do: [
      %{report: d.report, treatment: if(terminal?(d), do: :keep, else: :exclude), basis: d.basis}
    ]

  def terminal?(d), do: d.kind in [:adopt_success, :adopt_failure]

  def affected(%{kind: :withdraw_disposition} = d),
    do: d.supersedes |> Enum.flat_map(& &1.reports) |> Enum.uniq() |> Enum.sort()

  def affected(d), do: d |> treatments() |> Enum.map(& &1.report) |> Enum.sort()

  def bindings(intent) do
    intent.decisions
    |> Enum.with_index()
    |> Enum.reduce([], fn {w, index}, bindings ->
      retained =
        Enum.reject(bindings, fn b ->
          Enum.any?(
            w.decision.supersedes,
            &(&1.decision_index == b.decision_index and b.item.report in &1.reports)
          )
        end)

      retained ++ Enum.map(treatments(w.decision), &%{decision_index: index, item: &1})
    end)
  end

  def applicable(intent) do
    base = base(intent)

    Enum.filter(bindings(intent), fn b ->
      Enum.at(intent.decisions, b.decision_index).accepted_base === base
    end)
  end

  def supersessions(intent, decision) do
    affected = affected(decision)

    bindings(intent)
    |> Enum.filter(&(&1.item.report in affected))
    |> Enum.group_by(& &1.decision_index, & &1.item.report)
    |> Enum.map(fn {index, reports} -> %{decision_index: index, reports: Enum.sort(reports)} end)
    |> Enum.sort()
  end

  def excluded?(intent, report),
    do:
      Enum.any?(
        applicable(intent),
        &(&1.item.report === report and &1.item.treatment == :exclude)
      )

  def knowledge(intent, id) do
    classified =
      applicable(intent)
      |> Enum.filter(fn b ->
        Enum.at(intent.decisions, b.decision_index).decision.evidence != [] and
          Report.execution_id(b.item.report) == id
      end)

    kept =
      classified |> Enum.filter(&(&1.item.treatment == :keep)) |> Enum.map(& &1.item.report.kind)

    cond do
      :success in kept -> :success
      :failure in kept -> :failure
      :not_executed in kept -> :not_executed
      classified != [] -> nil
      intent.executions[id].result -> intent.executions[id].result.kind
      true -> nil
    end
  end

  def no_conflicts?(intent) do
    bindings = applicable(intent)

    Enum.all?(intent.executions, fn {_id, execution} ->
      not execution.conflict or conflict_covered?(intent, execution, bindings)
    end)
  end

  defp conflict_covered?(intent, execution, bindings) do
    Enum.all?(execution.reports, fn r ->
      Enum.any?(bindings, fn b ->
        b.item.report === r and
          Enum.at(intent.decisions, b.decision_index).decision.evidence != []
      end)
    end)
  end

  def no_unresolved_risk?(intent),
    do:
      Enum.all?(intent.executions, fn {id, e} ->
        is_nil(e.authorization) or knowledge(intent, id) != nil
      end)

  def old_success?(intent, current_id),
    do:
      Enum.any?(
        reports(intent),
        &(Report.execution_id(&1) != current_id and &1.kind == :success and
            not excluded?(intent, &1))
      )

  def evidence?(intent, report),
    do: report in reports(intent) and not excluded?(intent, report)

  def conflict_reports(intent),
    do: Enum.filter(reports(intent), &intent.executions[Report.execution_id(&1)].conflict)
end
