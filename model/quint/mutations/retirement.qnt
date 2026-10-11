// Deliberately conflate ordinary retirement with invalidation or judgment changes.
module ruleRetirementMutations {
  import repeatingRetirementFixtures.* from "../scenarios/repeating/retirement_fixtures"
  export repeatingRetirementFixtures.*
  const RETIREMENT_BUG: int

  action mutantInit = automaticRuleCommittedInit

  action mutantStep = {
    val before = authority.durable
    val accepted = before.decisions.head()
    val updated = if (RETIREMENT_BUG == 1) {
      ...before, decisions: List({ ...accepted,
        acceptedBase: { ...accepted.acceptedBase, phase: Closed } }),
    } else { ...before, revision: before.revision + 1 }
    val observed = observeRuleRetirement(external, before, updated, bothVersionPolicy, rule2v1.rule)
    // Forge this summary: actual bindings/revisions must independently expose the violation.
    val forged = { ...observed.ruleRetirements.head(), durableUnchanged: true }
    all {
      authority.online,
      authority' = { ...authority, durable: updated }, workers' = workers,
      network' = network, clock' = clock,
      external' = { ...observed, ruleRetirements: List(forged) },
    }
  }

  val mutantInvariant = ordinaryRuleRetirementSound
  run mutationCaughtTest = mutantInit.expect(commandSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(commandSafety))
}
