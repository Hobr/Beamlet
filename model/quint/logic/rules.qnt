// Version-pinned, Authority-checked rule definitions and conditions.
module coreLogicRules {
  import coreLogicOutcomes.* from "./outcomes"
  export coreLogicOutcomes.*

  pure val rule1v1: RuleRegistration = {
    rule: { id: 1, version: 1 }, kinds: Set(AdoptSuccess),
    queryRequired: true, evidenceRequired: false,
  }
  pure val rule2v1: RuleRegistration = {
    rule: { id: 2, version: 1 }, kinds: Set(ExcludeFromJudgment),
    queryRequired: false, evidenceRequired: false,
  }
  pure val rule4v1: RuleRegistration = {
    rule: { id: 4, version: 1 }, kinds: Set(AdoptSuccess, AdoptFailure),
    queryRequired: true, evidenceRequired: true,
  }
  pure val rule5v1: RuleRegistration = {
    rule: { id: 5, version: 1 }, kinds: Set(ExcludeAllEvidence),
    queryRequired: false, evidenceRequired: true,
  }
  // Same identity, narrower new semantics: a Worker report is no longer enough.
  pure val rule2v2: RuleRegistration = {
    ...rule2v1, rule: { id: 2, version: 2 }, queryRequired: true,
  }

  // Ordinary retirement changes a trusted registration input, never the Intent ledger.
  pure def retiredRulePolicy(p: ReconciliationPolicy, ref: RuleReference): ReconciliationPolicy =
    { ...p, registeredRules: p.registeredRules.filter(r => r.rule != ref) }

  pure def observeRuleRetirement(x: ExternalState, before: Ledger, after: Ledger,
    p: ReconciliationPolicy, ref: RuleReference): ExternalState = {
    val witness: RuleRetirementWitness = {
      rule: ref, previousRules: p.registeredRules,
      nextRules: retiredRulePolicy(p, ref).registeredRules,
      previousBindings: applicableBindings(before), nextBindings: applicableBindings(after),
      previousRevision: before.revision, nextRevision: after.revision, durableUnchanged: before == after,
    }
    { ...x, ruleRetirements: x.ruleRetirements.append(witness) }
  }

  pure def ruleConditionQualified(r: RuleRegistration, d: Decision): bool =
    r.kinds.contains(d.kind) and (not(r.queryRequired) or d.report.origin == ByQuery)
      and (not(r.evidenceRequired) or d.evidence.size() > 0)

  pure def registeredRuleQualified(rules: Set[RuleRegistration], d: Decision): bool = match d.actor {
    | Operator(_) => true
    | AutomaticRule(ref) => {
        val matches = rules.filter(r => r.rule == ref)
        matches.size() == 1 and matches.forall(r => ruleConditionQualified(r, d))
      }
  }
}
