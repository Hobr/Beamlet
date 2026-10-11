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
