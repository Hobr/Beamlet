// Deliberately broken rule-version handling; normal simulation never imports this module.
module ruleVersionMutations {
  import repeatingRuleFixtures.* from "../scenarios/repeating/rules_fixtures"
  export repeatingRuleFixtures.*
  const RULE_BUG: int

  action mutantInit =
    if (RULE_BUG == 3) ruleQueryPendingInit
    else if (RULE_BUG == 4) automaticRuleCommittedInit
    else if (RULE_BUG == 5) automaticRuleCommittedInit
      .then(sendReconciliationCommand(automaticV1Command)).expect(commandSafety)
    else if (RULE_BUG == 2) oldSuccessCurrentFailureInit
      .then(sendReconciliationCommand(automaticV2Command)).expect(commandSafety)
    else automaticRulePendingInit

  action mutantStep = {
    val before = authority.durable
    val request = if (RULE_BUG == 3) queryV1Command
      else if (RULE_BUG == 2) automaticV2Command else automaticV1Command
    val candidate = if (RULE_BUG == 3) {
      ...request, decision: { ...request.decision, actor: AutomaticRule(rule2v2.rule) }
    } else request
    val evaluated = if (RULE_BUG == 3) queryRulePolicy
      else if (RULE_BUG == 2) bothVersionPolicy else upgradedRulePolicy
    val updated =
      if (RULE_BUG == 1 or RULE_BUG == 2) {
        val applied = applyNewCommand(before, evaluated, candidate)
        // Independent snapshot checks must detect versions even with a forged admission flag.
        { ...applied, decisions: List({ ...applied.decisions.head(), actorQualified: true }) }
      } else if (RULE_BUG == 3)
        recordCommittedCommand(before, applyReconcile(before, evaluated, candidate.decision), request)
      else if (RULE_BUG == 4) {
        val original = before.decisions.head()
        val changed = original.rulesAtDecision.filter(r => r.rule != rule2v1.rule)
          .union(Set({ ...rule2v1, queryRequired: true }))
        { ...before, decisions: List({ ...original, rulesAtDecision: changed }) }
      } else before
    val reply = if (RULE_BUG == 5) CommandIneligible(request)
      else CommandCommitted(updated.commands.head())
    all {
      authority.online,
      authority' = { ...authority, durable: updated }, workers' = workers,
      network' = if (RULE_BUG == 5)
        network.exclude(Set(ReconcileRequest(request))).union(Set(ReconcileReply(reply))) else network,
      external' = if (RULE_BUG == 5)
        observeCommandHandling(external, before, updated, evaluated, request, reply) else external,
      clock' = clock,
    }
  }

  val mutantInvariant =
    if (RULE_BUG == 3) commandExecutionMatchesRequest
    else if (RULE_BUG == 5) commandHandlingSound
    else automaticRuleVersionsSound

  run mutationCaughtTest = mutantInit.expect(commandSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(commandSafety))
}
