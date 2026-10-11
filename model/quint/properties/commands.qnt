// Command identity, durability, atomicity, replay and access properties.
module corePropertiesCommands {
  import coreLogicCommands.* from "../logic/commands"
  export coreLogicCommands.*

  pure def commandIdentityUnique(l: Ledger, id: int): bool =
    commandsForId(l, id).length() + rejectionsForId(l, id).length() == 1

  val commandRecordsUnique = authority.durable.commands.foldl(true, (ok, r) =>
    ok and commandIdentityUnique(authority.durable, r.command.id))
    and authority.durable.rejections.foldl(true, (ok, r) =>
      ok and commandIdentityUnique(authority.durable, r.command.id))

  val rejectedCommandsImmutable = authority.durable.rejections ==
    authority.durable.rejectionCommits.foldl(List(), (rs, w) => rs.append(w.original))

  val rejectionQualified = authority.durable.rejectionCommits.foldl(true, (ok, w) =>
    ok and w.admitted and not(w.eligible) and w.original.result ==
      (if (w.original.command.decision.reviewedRevision != w.revisionAtRejection)
        ReviewStale({ revision: w.revisionAtRejection, current: w.currentAtRejection, reports: w.reportsAtRejection, view: w.viewAtRejection })
      else DecisionIneligible))

  val rejectionEffectsAtomic = authority.durable.rejectionCommits.foldl(true, (ok, w) =>
    ok and w.decisionsBefore == w.decisionsAfter and w.outcomesBefore == w.outcomesAfter
      and w.historyAfter == w.historyBefore + 1)
    and authority.durable.rejections.length() ==
      authority.durable.history.select(a => a.kind == CommandRejectionStored).length()

  val commandRecordsImmutable = authority.durable.commands ==
    authority.durable.commandCommits.foldl(List(), (rs, w) => rs.append(w.original))

  val commandExecutionMatchesRequest = authority.durable.commands.foldl(true, (ok, r) =>
    ok and {
      if (r.decisionIndex >= 0 and r.decisionIndex < authority.durable.decisions.length())
        authority.durable.decisions.nth(r.decisionIndex).decision == r.command.decision
      else false
    })

  val commandEffectsAtomic = authority.durable.commandCommits.foldl(true, (ok, w) =>
    ok and w.commandsAfter == w.commandsBefore + 1
      and w.decisionsAfter == w.decisionsBefore + 1
      and w.historyAfter == w.historyBefore + (if (decisionIsTerminal(w.original.command.decision)) 2 else 1))

  val commandResultsOriginal = authority.durable.commands.foldl(true, (ok, r) =>
    ok and r.outcomes == (if (decisionIsTerminal(r.command.decision))
      List(decisionOutcome(r.command.decision)) else List()))

  val commandRepliesSound = network.forall(m => match m {
    | ReconcileReply(reply) => match reply {
        | CommandCommitted(r) => authority.durable.commands.select(stored => stored == r).length() == 1
        | CommandIdentityConflict(c) => commandsForId(authority.durable, c.id)
            .select(r => r.command != c).length()
            + rejectionsForId(authority.durable, c.id).select(r => r.command != c).length() > 0
        | CommandStale(s) => authority.durable.rejections
            .select(r => r.command == s.command and r.result == ReviewStale({ revision: s.revision, current: s.current, reports: s.reports, view: s.view }))
            .length() == 1
        | CommandIneligible(c) => authority.durable.rejections
            .select(r => r.command == c and r.result == DecisionIneligible).length() == 1
        | CommandForbidden(_) => true
      }
    | _ => true
  })

  pure def commandHandlingCorrect(w: CommandHandlingWitness): bool =
    if (w.previous.length() > 0) {
      val original = w.previous.head()
      w.durableUnchanged and w.reply == (if (not(w.mayRead)) CommandForbidden(w.request)
        else if (original.command == w.request) CommandCommitted(original)
        else CommandIdentityConflict(w.request))
    } else if (w.rejectedPreviously.length() > 0) {
      val original = w.rejectedPreviously.head()
      w.durableUnchanged and w.reply == (if (not(w.mayRead)) CommandForbidden(w.request)
        else if (original.command == w.request) rejectionReply(original)
        else CommandIdentityConflict(w.request))
    } else if (not(w.maySubmit)) {
      w.durableUnchanged and w.reply == CommandForbidden(w.request)
    } else if (not(w.mayRead)) {
      w.resolutionStored and w.reply == CommandForbidden(w.request)
    } else if (w.request.decision.reviewedRevision != w.revisionAtHandling) {
      w.resolutionStored and w.reply == CommandStale({
        command: w.request, revision: w.revisionAtHandling, current: w.currentAtHandling, reports: w.reportsAtHandling,
        view: w.viewAtHandling,
      })
    } else if (not(w.eligible)) {
      w.resolutionStored and w.reply == CommandIneligible(w.request)
    } else match w.reply {
      | CommandCommitted(r) => r.command == w.request and w.resolutionStored
      | _ => false
    }

  val commandHandlingSound = external.commandHandling.foldl(true,
    (ok, w) => ok and commandHandlingCorrect(w))

  val commandReadAuthorized = external.commandHandling.foldl(true, (ok, w) =>
    ok and (w.mayRead or w.reply == CommandForbidden(w.request)))
}
