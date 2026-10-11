// Command identity, original results, rejection, access and observation logic.
module coreLogicCommands {
  import coreLogicReconciliation.* from "./reconciliation"
  export coreLogicReconciliation.*

  pure def commandsForId(l: Ledger, id: int): List[CommandRecord] =
    l.commands.select(r => r.command.id == id)

  pure def rejectionsForId(l: Ledger, id: int): List[RejectedCommandRecord] =
    l.rejections.select(r => r.command.id == id)

  pure def commandIdKnown(l: Ledger, id: int): bool =
    commandsForId(l, id).length() > 0 or rejectionsForId(l, id).length() > 0

  pure def submitActorAllowed(p: ReconciliationPolicy, d: Decision): bool = match d.actor {
    | Operator(id) => p.operators.contains(id)
    | AutomaticRule(id) => p.registeredRules.contains(id)
  }

  pure def commandSubmissionAllowed(p: ReconciliationPolicy, c: ReconciliationCommand, a: CommandAccess): bool =
    a.maySubmit and submitActorAllowed(p, c.decision)

  pure def canAcceptCommand(l: Ledger, p: ReconciliationPolicy, c: ReconciliationCommand): bool =
    not(commandIdKnown(l, c.id)) and submitActorAllowed(p, c.decision) and canReconcile(l, p, c.decision)

  // Record the submitted request separately from the decision actually applied.
  pure def recordCommittedCommand(before: Ledger, applied: Ledger, c: ReconciliationCommand): Ledger = {
    val record: CommandRecord = {
      command: c, outcomes: applied.outcomes, decisionIndex: before.decisions.length(),
    }
    val updated = { ...applied, commands: applied.commands.append(record) }
    val witness: CommandCommitWitness = {
      original: record,
      commandsBefore: before.commands.length(), commandsAfter: updated.commands.length(),
      decisionsBefore: before.decisions.length(), decisionsAfter: updated.decisions.length(),
      historyBefore: before.history.length(), historyAfter: updated.history.length(),
    }
    { ...updated, commandCommits: updated.commandCommits.append(witness) }
  }

  pure def applyNewCommand(l: Ledger, p: ReconciliationPolicy, c: ReconciliationCommand): Ledger =
    recordCommittedCommand(l, applyReconcileAndMaybeCommit(l, p, c.decision), c)

  pure def rejectionFor(l: Ledger, c: ReconciliationCommand): RejectedCommandRecord = {
    val result = if (not(decisionScopeCurrent(l, c.decision)))
      ReviewStale({ revision: l.revision, current: l.current, reports: l.reports, view: judgmentView(l) }) else DecisionIneligible
    { command: c, result: result }
  }

  pure def rejectionReply(r: RejectedCommandRecord): CommandReply = match r.result {
    | ReviewStale(s) => CommandStale({ command: r.command, revision: s.revision, current: s.current, reports: s.reports, view: s.view })
    | DecisionIneligible => CommandIneligible(r.command)
  }

  pure def recordRejectedCommand(l: Ledger, p: ReconciliationPolicy, c: ReconciliationCommand,
    a: CommandAccess): Ledger = {
    val record = rejectionFor(l, c)
    val updated = { ...l, rejections: l.rejections.append(record),
      history: l.history.append({ kind: CommandRejectionStored, exec: l.current }) }
    val witness: RejectionWitness = {
      original: record, admitted: commandSubmissionAllowed(p, c, a),
      eligible: canReconcile(l, p, c.decision),
      revisionAtRejection: l.revision, currentAtRejection: l.current, reportsAtRejection: l.reports,
      viewAtRejection: judgmentView(l),
      decisionsBefore: l.decisions.length(), decisionsAfter: updated.decisions.length(),
      outcomesBefore: l.outcomes, outcomesAfter: updated.outcomes,
      historyBefore: l.history.length(), historyAfter: updated.history.length(),
    }
    { ...updated, rejectionCommits: updated.rejectionCommits.append(witness) }
  }

  pure def processCommand(l: Ledger, p: ReconciliationPolicy, c: ReconciliationCommand,
    a: CommandAccess): Ledger =
    if (commandIdKnown(l, c.id) or not(commandSubmissionAllowed(p, c, a))) l
    else if (canAcceptCommand(l, p, c)) applyNewCommand(l, p, c)
    else recordRejectedCommand(l, p, c, a)

  pure def commandReplyWithAccess(l: Ledger, p: ReconciliationPolicy, c: ReconciliationCommand,
    a: CommandAccess): CommandReply = {
    val previous = commandsForId(l, c.id)
    val rejected = rejectionsForId(l, c.id)
    if (not(a.mayRead)) CommandForbidden(c)
    else if (previous.length() > 0) {
      val original = previous.head()
      if (original.command == c) CommandCommitted(original) else CommandIdentityConflict(c)
    } else if (rejected.length() > 0) {
      val original = rejected.head()
      if (original.command == c) rejectionReply(original) else CommandIdentityConflict(c)
    } else if (not(commandSubmissionAllowed(p, c, a))) CommandForbidden(c)
    else if (canAcceptCommand(l, p, c)) {
      val updated = applyNewCommand(l, p, c)
      CommandCommitted(updated.commands.nth(updated.commands.length() - 1))
    } else rejectionReply(rejectionFor(l, c))
  }

  pure def commandReplyFor(l: Ledger, p: ReconciliationPolicy, c: ReconciliationCommand): CommandReply =
    commandReplyWithAccess(l, p, c, fullCommandAccess)

  pure def observeCommandWithAccess(x: ExternalState, before: Ledger, after: Ledger,
    p: ReconciliationPolicy, c: ReconciliationCommand, a: CommandAccess, reply: CommandReply): ExternalState = {
    val witness: CommandHandlingWitness = {
      request: c, previous: commandsForId(before, c.id), rejectedPreviously: rejectionsForId(before, c.id),
      reply: reply, mayRead: a.mayRead, maySubmit: commandSubmissionAllowed(p, c, a),
      eligible: canReconcile(before, p, c.decision),
      resolutionStored: commandsForId(after, c.id).select(r => r.command == c).length() == 1
        or rejectionsForId(after, c.id).select(r => r.command == c).length() == 1,
      revisionAtHandling: before.revision, currentAtHandling: before.current, reportsAtHandling: before.reports,
      viewAtHandling: judgmentView(before),
      durableUnchanged: before == after,
    }
    { ...x, commandHandling: x.commandHandling.append(witness) }
  }

  pure def observeCommandHandling(x: ExternalState, before: Ledger, after: Ledger,
    p: ReconciliationPolicy, c: ReconciliationCommand, reply: CommandReply): ExternalState =
    observeCommandWithAccess(x, before, after, p, c, fullCommandAccess, reply)
}
