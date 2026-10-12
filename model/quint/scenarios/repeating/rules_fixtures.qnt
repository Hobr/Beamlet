// Rule registry snapshots are trusted Authority inputs, independent of Judgment Revision.
module repeatingRuleFixtures {
  import repeatingFixtures.* from "./fixtures"
  export repeatingFixtures.*

  // 同一规则 v1/v2 可并存;v2 要求查询来源,新命令须按明确指定的那一版解释.
  pure val bothVersionPolicy: ReconciliationPolicy = {
    ...reconciliationPolicy, registeredRules: Set(rule1v1, rule2v1, rule2v2),
  }
  pure val upgradedRulePolicy: ReconciliationPolicy = {
    ...reconciliationPolicy, registeredRules: Set(rule1v1, rule2v2),
  }
  pure val automaticV1Command: ReconciliationCommand = {
    ...exclusionCommand, decision: {
      ...exclusionCommand.decision, actor: AutomaticRule(rule2v1.rule),
    },
  }
  pure val automaticV2Command: ReconciliationCommand = {
    ...automaticV1Command, decision: {
      ...automaticV1Command.decision, actor: AutomaticRule(rule2v2.rule),
    },
  }
  pure val automaticV1Record: CommandRecord = {
    command: automaticV1Command, outcomes: List(), decisionIndex: 0,
  }

  action automaticRulePendingInit = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand(automaticV1Command)).expect(commandSafety)
  action automaticRuleCommittedInit = automaticRulePendingInit
    .then(receiveReconciliationCommand(bothVersionPolicy, automaticV1Command)).expect(commandSafety)
  action retiredRuleRejectedInit = automaticRulePendingInit
    .then(receiveReconciliationCommand(upgradedRulePolicy, automaticV1Command)).expect(commandSafety)

  def automaticQueryV2: ReconciliationCommand = {
    id: 2, decision: proposeDecision(authority.durable, querySuccess,
      ExcludeFromJudgment, AutomaticRule(rule2v2.rule)),
  }
  pure val queryRulePolicy: ReconciliationPolicy = {
    ...upgradedRulePolicy, excludable: Set(success1, querySuccess),
  }
  pure val queryV1Command: ReconciliationCommand = {
    id: 2, decision: {
      ...automaticV1Command.decision, report: querySuccess, reviewedRevision: 8,
    },
  }

  action ruleQueryPendingInit = oldSuccessCurrentFailureInit
    .then(queryExternal(1, 3)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .then(sendReconciliationCommand(queryV1Command)).expect(commandSafety)

  val pinnedV1Witness = authority.durable.decisions.select(w => match w.decision.actor {
    | AutomaticRule(ref) => ref == rule2v1.rule
    | _ => false
  }).length() > 0
  val pinnedV2Witness = authority.durable.decisions.select(w => match w.decision.actor {
    | AutomaticRule(ref) => ref == rule2v2.rule
    | _ => false
  }).length() > 0

  // 非确定切换可信登记输入以检查版本兼容性;单向普通退役另用 retirementStep.
  action ruleVersionStep = any {
    stepWithCommands(bothVersionPolicy), receiveAnyReconciliationCommand(upgradedRulePolicy),
    sendReconciliationCommand({ ...automaticV1Command, id: 3, decision:
      proposeDecision(authority.durable, success1, ExcludeFromJudgment, AutomaticRule(rule2v1.rule)) }),
    sendReconciliationCommand({ ...automaticV2Command, id: 4, decision:
      proposeDecision(authority.durable, success1, ExcludeFromJudgment, AutomaticRule(rule2v2.rule)) }),
    sendReconciliationCommand(automaticQueryV2),
    receiveAnyReconciliationCommand(queryRulePolicy),
  }
}
