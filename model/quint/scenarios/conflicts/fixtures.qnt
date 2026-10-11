// Defensive checked-ingress simulation, bounded contract inputs and legal prefixes.
module conflictFixtures {

  import beamletCore.* from "../../beamletCore"
  export beamletCore.*

  pure val t1: Token = { exec: 1, worker: 1, incarnation: 1, generation: 1 }

  pure val t2: Token = { exec: 2, worker: 2, incarnation: 1, generation: 1 }

  pure val success1: Report = { id: 2, exec: 1, kind: Success, origin: ByWorker(t1) }

  pure val failure2: Report = { id: 2, exec: 2, kind: Failure, origin: ByWorker(t2) }

  pure val disputedFailure: Report = { id: 3, exec: 1, kind: Failure, origin: ByQuery }

  pure val querySuccess: Report = { id: 4, exec: 1, kind: Success, origin: ByQuery }

  pure val querySuccess2: Report = { id: 3, exec: 2, kind: Success, origin: ByQuery }

  pure def keep(r: Report): EvidenceDisposition =
    { report: r, treatment: KeepEvidence, basis: VerifiedCompletion }

  pure def discardEvidence(r: Report): EvidenceDisposition =
    { report: r, treatment: ExcludeEvidence, basis: ContractExclusion }

  pure val excludeOldConflict = Set(discardEvidence(success1), keep(disputedFailure))

  pure val acceptOldConflict = Set(keep(success1), discardEvidence(disputedFailure), keep(querySuccess))

  pure val failCurrentConflict = excludeOldConflict.union(Set(keep(failure2)))

  pure val resolveBothConflicts =
    excludeOldConflict.union(Set(discardEvidence(failure2), keep(querySuccess2)))

  pure val excludeAllConflict = Set(discardEvidence(success1), discardEvidence(disputedFailure))

  pure val excludeAllBoth = excludeAllConflict.union(Set(discardEvidence(failure2), discardEvidence(querySuccess2)))

  pure val excludeAllAcross = excludeAllConflict.union(Set(discardEvidence(failure2)))

  pure val failWithUnknownOld = excludeAllConflict.union(Set(keep(failure2)))

  pure val policy: ReconciliationPolicy = {
    operators: Set(1), registeredRules: Set(1, 2, 4, 5), excludable: Set(success1),
    resolutions: Set(excludeOldConflict, acceptOldConflict, failCurrentConflict, resolveBothConflicts,
      excludeAllConflict, excludeAllBoth, excludeAllAcross, failWithUnknownOld),
  }

  // Trusted ingress boundary, deliberately separate from resource-generated queryExternal.
  // Authentication, parsing and the truth of the evidence remain assumptions.
  action offerCheckedEvidence(r: Report): bool = all {
    r.origin == ByQuery, REPORT_IDS.contains(r.id), EXECUTIONS.contains(r.exec),
    reportSourceValid(authority.durable, r), not(authority.durable.reports.contains(r)),
    not(network.contains(ResultReport(r))),
    authority' = authority, workers' = workers,
    network' = network.union(Set(ResultReport(r))),
    external' = { ...external, emitted: external.emitted.union(Set(r)) }, clock' = clock,
  }

  action grantedReplacementInit = init.expect(commandSafety)
    .then(createExecution(1)).expect(commandSafety)
    .then(claimExecution(1, 1)).expect(commandSafety)
    .then(requestStart(t1)).expect(commandSafety)
    .then(authorizeStart(t1)).expect(commandSafety)
    .then(receiveGrant(t1)).expect(commandSafety)
    .then(moveClockTo(2)).expect(commandSafety)
    .then(expireLease(1)).expect(commandSafety)
    .then(replaceExecution(1, 2)).expect(commandSafety)
    .then(claimExecution(2, 2)).expect(commandSafety)
    .then(requestStart(t2)).expect(commandSafety)
    .then(authorizeStart(t2)).expect(commandSafety)
    .then(receiveGrant(t2)).expect(commandSafety)

  action readyInit = grantedReplacementInit
    .then(callExternal(t1)).expect(commandSafety)
    .then(completeAtResource(1, Success)).expect(commandSafety)
    .then(publishCompletion(t1)).expect(commandSafety)
    .then(receiveReport(success1)).expect(commandSafety)
    .then(callExternal(t2)).expect(commandSafety)
    .then(completeAtResource(2, Failure)).expect(commandSafety)
    .then(publishCompletion(t2)).expect(commandSafety)
    .then(receiveReport(failure2)).expect(commandSafety)

  action conflictInit = readyInit
    .then(offerCheckedEvidence(disputedFailure)).expect(commandSafety)
    .then(receiveReport(disputedFailure)).expect(commandSafety)

  action queriedConflictInit = conflictInit
    .then(offerCheckedEvidence(querySuccess)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)

  action bothConflictsInit = conflictInit
    .then(offerCheckedEvidence(querySuccess2)).expect(commandSafety)
    .then(receiveReport(querySuccess2)).expect(commandSafety)

  pure def conflictDecision(l: Ledger, r: Report, kind: DecisionKind,
    items: Set[EvidenceDisposition], actor: DecisionActor): Decision =
    withSupersessions(l, { ...proposeDecision(l, r, kind, actor), evidence: items })

  def exclusion: Decision =
    conflictDecision(authority.durable, success1, ExcludeFromJudgment, excludeOldConflict, Operator(1))

  def adoption: Decision =
    conflictDecision(authority.durable, querySuccess, AdoptSuccess, acceptOldConflict, Operator(1))

  def failure: Decision =
    conflictDecision(authority.durable, failure2, AdoptFailure, failCurrentConflict, Operator(1))

  pure val exclusionCommand: ReconciliationCommand = {
    id: 1, decision: {
      kind: ExcludeFromJudgment, report: success1, actor: Operator(1), basis: ContractExclusion,
      reviewedRevision: 8, evidence: excludeOldConflict, supersedes: Set(),
    },
  }

  pure val allExclusionCommand: ReconciliationCommand = {
    id: 1, decision: { ...exclusionCommand.decision, kind: ExcludeAllEvidence, evidence: excludeAllConflict },
  }

  action allExcludedInit = conflictInit
    .then(sendReconciliationCommand(allExclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, allExclusionCommand)).expect(commandSafety)

  action resolvedConflictInit = conflictInit
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, exclusionCommand)).expect(commandSafety)

  pure val exclusionRecord: CommandRecord =
    { command: exclusionCommand, outcomes: List(), decisionIndex: 0 }

  action offerAnyCheckedEvidence = {
    nondet r = Set(disputedFailure, querySuccess, querySuccess2).oneOf()
    offerCheckedEvidence(r)
  }

  action proposeConflictCommand = {
    nondet id = Set(1, 2, 3, 4).oneOf()
    nondet candidate = Set(
      { report: failure2, kind: ExcludeAllEvidence, items: excludeAllAcross },
      { report: success1, kind: ExcludeAllEvidence, items: excludeAllConflict },
      { report: querySuccess2, kind: ExcludeAllEvidence, items: excludeAllBoth },
      { report: failure2, kind: AdoptFailure, items: failWithUnknownOld },
      { report: success1, kind: ExcludeFromJudgment, items: excludeOldConflict },
      { report: querySuccess, kind: AdoptSuccess, items: acceptOldConflict },
      { report: failure2, kind: AdoptFailure, items: failCurrentConflict },
      { report: querySuccess2, kind: AdoptSuccess, items: resolveBothConflicts }).oneOf()
    nondet actor = Set(Operator(1), Operator(2), AutomaticRule(4), AutomaticRule(5)).oneOf()
    sendReconciliationCommand({
      id: id, decision: conflictDecision(authority.durable, candidate.report, candidate.kind, candidate.items, actor),
    })
  }

  action conflictStep = any {
    stepWithCommands(policy), offerAnyCheckedEvidence, proposeConflictCommand,
  }

  def freshAllExclusion: ReconciliationCommand = {
    id: 2, decision: conflictDecision(authority.durable, success1,
      ExcludeAllEvidence, excludeAllConflict, Operator(1)),
  }

  def freshPartialExclusion: ReconciliationCommand = {
    id: 2, decision: conflictDecision(authority.durable, success1,
      ExcludeFromJudgment, excludeOldConflict, Operator(1)),
  }

  pure val replacementCommand: ReconciliationCommand = {
    id: 2, decision: {
      ...allExclusionCommand.decision, reviewedRevision: 9,
      supersedes: Set({ decisionIndex: 0, reports: Set(success1, disputedFailure) }),
    },
  }

  pure val wideExclusionCommand: ReconciliationCommand = {
    id: 1, decision: {
      ...allExclusionCommand.decision, report: failure2, evidence: excludeAllAcross,
    },
  }

  action wideExcludedInit = conflictInit
    .then(sendReconciliationCommand(wideExclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, wideExclusionCommand)).expect(commandSafety)

  action partiallySupersededInit = wideExcludedInit
    .then(sendReconciliationCommand(freshPartialExclusion)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, freshPartialExclusion)).expect(commandSafety)

  val supersessionWitness = supersessionReached

  val allExcludedWitness = allExcludedReached

  val conflictSafety = commandSafety

  val conflictDispositionWitness = conflictDispositionReached

  val conflictSuccessWitness = conflictSuccessReached

  val conflictFailureWitness = conflictFailureReached
}
