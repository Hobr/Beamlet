// Core safety properties and their independent evidence checks.
module corePropertiesCore {
  import coreLogicLeases.* from "../logic/leases"
  export coreLogicLeases.*
  import coreLogicOutcomes.* from "../logic/outcomes"
  export coreLogicOutcomes.*

  val startupsQualified = authority.durable.starts.foldl(true, (ok, s) =>
    ok and s.openAtGrant and s.currentAtGrant and s.leaseValidAtGrant)

  val oneStartPerExecution = EXECUTIONS.forall(e =>
    authority.durable.starts.select(s => s.token.exec == e).length() <= 1)

  val expirySticky = EXECUTIONS.forall(e => stickyLease(authority.durable, e))

  val invocationsAuthorized = external.invocations.foldl(true, (ok, call) =>
    ok and call.incarnationAtCall == call.token.incarnation
      and authority.durable.starts.select(s => s.token == call.token).length() == 1)

  val oneCallPerExecution = EXECUTIONS.forall(e =>
    external.invocations.select(call => call.token.exec == e).length() <= 1)

  val commitsQualified = authority.durable.commits.foldl(true, (ok, c) =>
    ok and c.openAtCommit and c.sourceEligible)

  val outcomeAuditAtomic = authority.durable.outcomes.length() == authority.durable.commits.length()
    and authority.durable.outcomes.length()
      == authority.durable.history.select(a => a.kind == OutcomeStored).length()

  val replacementsSafe = authority.durable.retries.foldl(true, (ok, r) => ok and r.safeAtReplacement)

  val notExecutedProofSound = EXECUTIONS.forall(e =>
    (authority.durable.attempts.get(e).knowledge == NotExecutedKnown) implies
      (external.noFuture.contains(e) and not(external.effects.contains(e))))

  val receiptsOnlyForStored = network.forall(m => match m {
    | StoredReceipt(r) => authority.durable.reports.contains(r) | _ => true
  }) and WORKERS.forall(w => workers.get(w).receipts.forall(r => authority.durable.reports.contains(r)))

  val reportAuditAtomic = authority.durable.reports.size()
    == authority.durable.history.select(a => a.kind == EvidenceStored).length()

  val resolvedKnowledgeCoherent = EXECUTIONS.forall(e =>
    (authority.durable.attempts.get(e).knowledge != NoKnowledge) implies
      authority.durable.attempts.get(e).phase == Resolved)

  pure def grantMatchesHistory(l: Ledger, e: int): bool = {
    val starts = l.starts.select(s => s.token.exec == e)
    match l.attempts.get(e).grant {
      | NoGrant => starts.length() == 0
      | StartGrant(t) => t.exec == e and starts.length() == 1
          and starts.select(s => s.token == t).length() == 1
    }
  }

  pure def knowledgeHasEvidence(l: Ledger, e: int): bool = {
    val known = l.attempts.get(e).knowledge
    known == NoKnowledge or l.reports.exists(r =>
      r.exec == e and knowledgeOf(r.kind) == known and reportSourceValid(l, r))
  }

  val grantsPersist = EXECUTIONS.forall(e => grantMatchesHistory(authority.durable, e))

  val knowledgeEvidenced = EXECUTIONS.forall(e => knowledgeHasEvidence(authority.durable, e))

  val reportsAuthenticated = authority.durable.reports.forall(r => reportSourceValid(authority.durable, r))

  val commitSnapshotsMatch = authority.durable.commits.foldl(List(), (xs, c) => xs.append(c.outcome))
    == authority.durable.outcomes

  // Check evidence available at commit, not reports that might arrive afterward.
  val failureRespectsOldSuccess = authority.durable.commits.foldl(true, (ok, c) =>
    ok and ((c.outcome.kind == OutcomeFailed) implies not(c.oldSuccessAtCommit)))

  val outcomeUnique = authority.durable.outcomes.length() <= 1 and authority.durable.commits.length() <= 1

  val closedIffOutcome = (authority.durable.phase == Closed)
                         iff (authority.durable.outcomes.length() > 0)

  val outcomeImmutable = authority.durable.outcomes == authority.durable.firstOutcome
}
