// Frame-complete decision and command protocol transitions.
module coreActionsReconciliation {
  import coreLogicCommands.* from "../logic/commands"
  export coreLogicCommands.*

  action reconcileDecision(p: ReconciliationPolicy, d: Decision): bool = all {
    authority.online, canReconcile(authority.durable, p, d),
    authority' = { ...authority, durable: applyReconcileAndMaybeCommit(authority.durable, p, d) },
    workers' = workers, network' = network, external' = external, clock' = clock,
  }

  action proposeAnyReconciliation(p: ReconciliationPolicy): bool = all {
    authority.durable.reports.size() > 0,
    nondet r = authority.durable.reports.oneOf()
    nondet kind = Set(AdoptSuccess, ExcludeFromJudgment).oneOf()
    nondet actor = Set(Operator(1), Operator(2), AutomaticRule({ id: 1, version: 1 }), AutomaticRule({ id: 2, version: 1 }), AutomaticRule({ id: 3, version: 1 })).oneOf()
    reconcileDecision(p, proposeDecision(authority.durable, r, kind, actor)),
  }

  action sendReconciliationCommand(c: ReconciliationCommand): bool = all {
    Set(1, 2, 3, 4).contains(c.id), not(network.contains(ReconcileRequest(c))),
    authority' = authority, workers' = workers,
    network' = network.union(Set(ReconcileRequest(c))),
    external' = external, clock' = clock,
  }

  action receiveCommandWithAccess(p: ReconciliationPolicy, c: ReconciliationCommand, a: CommandAccess): bool = {
    val before = authority.durable
    val reply = commandReplyWithAccess(before, p, c, a)
    val updated = processCommand(before, p, c, a)
    val observed = observeCommandWithAccess(external, before, updated, p, c, a, reply)
    val mark = match reply {
      | CommandCommitted(_) => if (commandsForId(before, c.id).length() > 0) "commandReplay" else "commandCommitted"
      | CommandStale(_) => if (commandIdKnown(before, c.id)) "commandReplay" else "staleCommandRejected"
      | CommandIdentityConflict(_) => "commandIdentityConflict"
      | CommandIneligible(_) => if (commandIdKnown(before, c.id)) "commandReplay" else "commandIneligible"
      | CommandForbidden(_) => "commandForbidden"
    }
    all {
      authority.online, network.contains(ReconcileRequest(c)),
      authority' = { ...authority, durable: updated }, workers' = workers,
      network' = network.exclude(Set(ReconcileRequest(c))).union(Set(ReconcileReply(reply))),
      external' = { ...observed, marks: external.marks.union(Set(mark))
        .union(if (not(a.mayRead)) Set("readDenied") else Set())
        .union(if (a.mayRead and not(commandSubmissionAllowed(p, c, a))
          and (commandsForId(before, c.id).select(r => r.command == c).length()
            + rejectionsForId(before, c.id).select(r => r.command == c).length() == 1))
          Set("readonlyReplay") else Set()) },
      clock' = clock,
    }
  }

  action receiveReconciliationCommand(p: ReconciliationPolicy, c: ReconciliationCommand): bool =
    receiveCommandWithAccess(p, c, fullCommandAccess)

  action receiveAnyReconciliationCommand(p: ReconciliationPolicy): bool = {
    val candidates = network.filter(m => match m { | ReconcileRequest(_) => true | _ => false })
    all {
      candidates.size() > 0,
      nondet m = candidates.oneOf()
      match m {
        | ReconcileRequest(c) => {
            nondet submit = Set(true, false).oneOf()
            nondet read = Set(true, false).oneOf()
            receiveCommandWithAccess(p, c, { maySubmit: submit, mayRead: read })
          }
        | _ => invalidMessageVariant
      },
    }
  }

  action proposeAnyCommand: bool = all {
    authority.durable.reports.size() > 0,
    nondet r = authority.durable.reports.oneOf()
    nondet kind = Set(AdoptSuccess, ExcludeFromJudgment).oneOf()
    nondet actor = Set(Operator(1), Operator(2), AutomaticRule({ id: 1, version: 1 }), AutomaticRule({ id: 2, version: 1 }), AutomaticRule({ id: 3, version: 1 })).oneOf()
    nondet id = Set(1, 2, 3, 4).oneOf()
    sendReconciliationCommand({
      id: id, decision: proposeDecision(authority.durable, r, kind, actor),
    }),
  }

  // Candidate generation represents a caller retaining the original request.
  // It does not define a client persistence or authentication implementation.
  action resendCommittedCommand = all {
    authority.durable.commands.length() + authority.durable.rejections.length() > 0,
    val accepted = authority.durable.commands.foldl(Set(), (cs, r) => cs.union(Set(r.command)))
    val originals = authority.durable.rejections.foldl(accepted, (cs, r) => cs.union(Set(r.command)))
    nondet c = originals.oneOf()
    sendReconciliationCommand(c),
  }
}
