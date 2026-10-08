// Deliberately incorrect cross-boundary transitions live only in this test module.
// Each test first checks a weaker local property, then the independent global detector.
module negative_controls_test {
  import architectureTypes.* from "./types"
  import architecture(RUNS = Set(0, 1), SLOTS = Set(0, 1), ATTEMPT_SLOTS = Set(0, 1, 2), QUEUE_LIMIT = 12, COMMAND_LIMIT = 32).* from "./architecture"
  pure val e = (0, 0)
  pure val a = (e, 0)
  pure val b = (e, 1)
  pure val c = (e, 2)
  run pending = init.then(appendInput(0, 0, 1)).then(evaluate(0, 0, InvokeStep, 0, NonRepeatable)).then(commit(0))
  run unknownPrefix = pending.then(admit(e, a, 0, 0, 0)).then(enter(a, 0)).then(ownerFault(0, false)).then(lose(a))
  action badOwnerEntry = advance({...applyEnter(s, a, 1), attempts: s.attempts.setBy(a, at => {...at, entered: true, calls: 1})})
  action badDuplicateOutcome = advance(recordOutcome(s, e, OkResult, Success, false, 0))
  action badStaleCommit = advance(applyCommit(s, 0))
  action badReusePermit = advance(applyAdmit({...s, effects: s.effects.setBy(e, ef => {...ef, permit: 1})}, e, c, 2))
  // These mutations bypass the production guard and forge its audit booleans.
  // Independent pre-state checks must still reject them.
  action badForgedActiveGrant = {
    val changed = applyAdmit(s, e, a, 0)
    advance({...changed, grants: changed.grants.map(g => {...g, active: true, currentController: g.controller})})
  }
  action badForgedActiveCommit = {
    val held = {...s, proposals: s.proposals.setBy(0, pp => {...pp, host: s.runs.get(0).host})}
    val changed = applyCommit(held, 0)
    advance({...changed, commits: changed.commits.map(f => {...f, active: true, currentHost: f.host})})
  }
  action badOriginalRevision = advance(applyCommand(s, 0, {...emptyCommand, tag: AdmissionCommand, revision: 999}))
  action badObservationOverwrite = advance({...s, observationIds: s.observationIds.setBy(4, k => {...k, payload: 1})})
  action unexplainedStall = advance({...s, runs: s.runs.setBy(0, rr => {...rr, cursor: 1})})
  run forgedActiveGrantTest = pending.then(control(0, Suspended)).then(badForgedActiveGrant).expect(G02 and not(referenceSafety))
  run forgedActiveCommitTest = init.then(appendInput(0, 0, 1)).then(evaluate(0, 0, InvokeStep, 0, NonRepeatable)).then(control(0, Suspended)).then(badForgedActiveCommit).expect(G04 and not(referenceSafety))
  run originalConditionGuardBypassTest = pending.then(badOriginalRevision).expect(G02 and not(referenceSafety))
  run observationKeyOverwriteTest = pending.then(admit(e, a, 0, 0, 0)).then(enter(a, 0)).then(complete(a, Success)).then(command(0, {...emptyCommand, tag: ObservationCommand, observation: Success, observationId: 4})).then(badObservationOverwrite).expect(not(referenceSafety))
  run noBlanketPermissionFallbackTest = init.then(permission(ExportOp)).then(unexplainedStall).expect(not(G08))
  run ownerInheritanceTest = pending.then(admit(e, a, 0, 0, 0)).then(badOwnerEntry).expect(s.attempts.get(a).calls == 1 and not(G02) and not(referenceSafety))
  run duplicateTerminalReplyTest = pending.then(admit(e, a, 0, 0, 0)).then(enter(a, 0)).then(complete(a, Success)).then(observe(a, 0)).then(badDuplicateOutcome).expect(s.effects.get(e).result == OkResult and not(G03))
  run staleProposalTest = init.then(appendInput(0, 0, 1)).then(evaluate(0, 0, InvokeStep, 0, NonRepeatable)).then(takeover(0, false)).then(badStaleCommit).expect(s.runs.get(0).revision == 1 and not(G04) and not(referenceSafety))
  run oneUsePermitTest = unknownPrefix.then(resolve(e, 2, RepeatOp)).then(admit(e, b, 1, 3, 0)).then(ownerFault(1, false)).then(lose(b)).then(badReusePermit).expect(ATTEMPTS.filter(aid => aid._1 == e and s.attempts.get(aid).phase == Admitted).size() == 1 and not(G02))
}
