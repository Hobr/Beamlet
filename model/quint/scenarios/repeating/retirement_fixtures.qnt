// Ordinary retirement boundaries and fixed post-retirement trusted policy inputs.
module repeatingRetirementFixtures {
  import repeatingRuleFixtures.* from "./rules_fixtures"
  export repeatingRuleFixtures.*

  pure val retiredV1Policy = retiredRulePolicy(bothVersionPolicy, rule2v1.rule)

  // 先接受 v1 处置再退役:既有处置与原命令结果保留,只阻止后续新提交使用该版本.
  action ordinaryRetirementInit = automaticRuleCommittedInit
    .then(retireRuleVersion(bothVersionPolicy, rule2v1.rule)).expect(commandSafety)

  action retirementBeforeDecisionInit = automaticRulePendingInit
    .then(retireRuleVersion(bothVersionPolicy, rule2v1.rule)).expect(commandSafety)

  action retirementAfterClosureInit = automaticRuleCommittedInit
    .then(finishFailure(2)).expect(commandSafety)
    .then(retireRuleVersion(bothVersionPolicy, rule2v1.rule)).expect(commandSafety)

  def freshRetiredV1Command: ReconciliationCommand = {
    id: 3, decision: proposeDecision(authority.durable, success1,
      ExcludeFromJudgment, AutomaticRule(rule2v1.rule)),
  }

  val retiredDispositionUsedWitness = external.ruleRetirements.length() > 0
    and authority.durable.outcomes == List({ kind: OutcomeFailed, value: 0, exec: Current(2) })
  val retirementBindingPreservedWitness = external.ruleRetirements.foldl(false, (found, w) =>
    found or (w.previousBindings.size() > 0 and w.previousBindings == w.nextBindings))

  // Neither branch restores v1. No witness field is an execution guard.
  action retirementStep = any {
    stepWithCommands(retiredV1Policy), receiveAnyReconciliationCommand(queryRulePolicy),
    sendReconciliationCommand(freshRetiredV1Command), sendReconciliationCommand(automaticQueryV2),
  }
}
