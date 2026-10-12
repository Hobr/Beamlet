// Choose only parameters used by one operation, avoiding unrelated Cartesian products.
module multiIntentScheduling {
  import multiIntentCallerProperties.* from "./caller_properties"
  export multiIntentCallerProperties.*
  action disabledMulti = all { false, holdRuntime, callerRounds' = callerRounds, agentLocals' = agentLocals }
  action dispatchMulti(envelope: ScopedMessage): bool = match envelope.message {
    | StartReply(t) => multiGrant(envelope.intent, envelope, t)
    | ResultReport(r) => multiReceive(envelope.intent, envelope, r)
    | StoredReceipt(r) => multiReceipt(envelope.intent, envelope, r)
    | StartRequest(_) => disabledMulti
  }
  action scheduleSubmission = {
    nondet c = CALLS.oneOf()
    val round = callerRounds.get(c)
    nondet dep = (if (round.exists) round.dependencies else Set(dependencyA)).oneOf()
    val owner = if (round.exists) round.owner else 1
    any { multiSend(owner, dep.request), multiSubmit(owner, dep.request) }
  }
  action scheduleReply = all { multiNetwork.replies.size() > 0,
    nondet reply = multiNetwork.replies.oneOf()
    multiResolve(reply.agent, reply.reply)
  }
  action scheduleRead = {
    nondet a = AGENTS.oneOf()
    all { agentLocals.get(a).refs.size() > 0,
      nondet ref = agentLocals.get(a).refs.oneOf()
      readDependency(a, ref)
    }
  }
  action scheduleCollect = { nondet c = CALLS.oneOf()
    all { callerRounds.get(c).exists, collectRound(callerRounds.get(c).owner, c) } }
  action scheduleRound = { nondet a = AGENTS.oneOf() nondet c = CALLS.oneOf()
    openRound(a, c, Set(dependencyA, dependencyB)) }
  action scheduleExecution = {
    nondet i = INTENTS.oneOf()
    nondet e = EXECUTIONS.oneOf()
    nondet w = WORKERS.oneOf()
    nondet h = Set(syncHandler, callbackHandler, queryHandler, idempotentHandler).oneOf()
    val l = multiStore.intents.get(i).ledger
    val t = if (l.attempts.get(e).lease.claimed) tokenFor(l, e)
      else { ...t1, exec: e, worker: w, incarnation: sharedWorkers.get(w).incarnation }
    any { multiCreate(i, e), multiClaim(i, e, w), multiRequest(i, t), multiAuthorize(i, t, h),
      multiCall(i, t), multiPublish(i, t, true), multiPublish(i, t, false),
      multiReplace(i, 1, 2), multiStop(i, e) }
  }
  action scheduleCompletion = { nondet i = INTENTS.oneOf() nondet e = EXECUTIONS.oneOf()
    nondet kind = Set(Success, Failure).oneOf() nondet value = Set(1, 2).oneOf()
    multiComplete(i, e, kind, value) }
  action scheduleResourceReport = { nondet i = INTENTS.oneOf() nondet e = EXECUTIONS.oneOf()
    nondet id = REPORT_IDS.oneOf() any { multiCallback(i, e, id), multiQuery(i, e, id) } }
  action scheduleDelivery = all { multiNetwork.messages.size() > 0,
    nondet envelope = multiNetwork.messages.oneOf() dispatchMulti(envelope) }
  action healthyMultiStep = any { scheduleSubmission, scheduleReply, scheduleRead, scheduleCollect,
    scheduleRound, scheduleExecution, scheduleCompletion, scheduleResourceReport, scheduleDelivery }

  action scheduleWorkerFault = { nondet w = WORKERS.oneOf() any { sharedWorkerCrash(w), sharedWorkerRestart(w) } }
  action scheduleAgentFault = { nondet a = AGENTS.oneOf() any { crashAgent(a), restartAgent(a) } }
  action scheduleClock = { nondet n = CLOCK_VALUES.oneOf() multiClockMove(n) }
  action scheduleLeaseFault = {
    nondet i = INTENTS.oneOf() nondet e = EXECUTIONS.oneOf()
    val l = multiStore.intents.get(i).ledger
    val t = if (l.attempts.get(e).lease.claimed) tokenFor(l, e) else t1
    any { multiExpire(i, e), multiRenew(i, t), multiResendGrant(i, t) }
  }
  action scheduleLoss = all { multiNetwork.messages.size() > 0,
    nondet envelope = multiNetwork.messages.oneOf() multiLoseMessage(envelope) }
  action scheduleReplyLoss = all { multiNetwork.replies.size() > 0,
    nondet reply = multiNetwork.replies.oneOf() multiLoseSubmissionReply(reply.agent, reply.reply) }
  action scheduleRedelivery = {
    nondet i = INTENTS.oneOf()
    all { resources.get(i).emitted.size() > 0,
      nondet r = resources.get(i).emitted.oneOf()
      any { multiRedeliver(i, r), multiDuplicate(i, r) }
    }
  }
  action scheduleCancel = { nondet i = INTENTS.oneOf() multiCancel(i) }
  action multiFaultStep = any { scheduleWorkerFault, scheduleAgentFault, scheduleClock, scheduleLeaseFault,
    scheduleLoss, scheduleReplyLoss, scheduleRedelivery, scheduleCancel, multiAvailability(false), multiAvailability(true) }
  action multiStep = any { healthyMultiStep, multiFaultStep }
}
