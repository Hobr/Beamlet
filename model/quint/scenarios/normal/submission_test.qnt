// Real normal-use prefixes; no direct resetting of durable protocol state.
module normalSubmissionTests {
  import normalUseProfile.* from "../../beamletNormalUse"
  export normalUseProfile.*

  action syncRunningInit = preparedInit.then(normalAuthorize(t1, syncHandler))
    .then(normalGrant(t1)).then(normalCall(t1))
  action succeededInit = syncRunningInit.then(normalComplete(1, Success, 1))
    .then(normalPublish(t1)).then(normalReceive(completionReport(external, t1)))

  run stableSubmissionReplayTest = submittedInit.expect(normalSafety)
    .then(loseSubmissionReply).then(sendSubmission(request)).then(receiveSubmission(request))
    .expect(normalSafety).expect(usage.entries.length() == 1)
    .expect(usage.replies.contains({ request: request, result: ExistingIntent({ id: 1, outcomes: List() }) }))

  run conflictingDefinitionTest = submittedInit
    .then(sendSubmission({ ...request, definition: { ...definition, input: 2 } }))
    .then(receiveSubmission({ ...request, definition: { ...definition, input: 2 } }))
    .expect(normalSafety).expect(identityConflictWitness and usage.entries.length() == 1)
    .expect(focused(usage).request.definition == definition)

  run operationVersionConflictTest = submittedInit
    .then(sendSubmission({ ...request, definition: { ...definition, operation: 2 } }))
    .then(receiveSubmission({ ...request, definition: { ...definition, operation: 2 } }))
    .expect(normalSafety).expect(identityConflictWitness and usage.entries.length() == 1)

  run hardConstraintConflictTest = submittedInit
    .then(sendSubmission({ ...request, definition: { ...definition, constraint: 2 } }))
    .then(receiveSubmission({ ...request, definition: { ...definition, constraint: 2 } }))
    .expect(normalSafety).expect(identityConflictWitness)

  run namespaceSeparatesIdentityTest = submittedInit
    .then(sendSubmission({ ...request, identity: StableKey({ namespace: 2, key: 1 }) }))
    .then(receiveSubmission({ ...request, identity: StableKey({ namespace: 2, key: 1 }) }))
    .expect(normalSafety).expect(usage.entries.length() == 2)
    .expect(usage.entries.nth(0).context != usage.entries.nth(1).context)

  run unkeyedAlwaysCreatesTest = normalInit
    .then(sendSubmission({ ...request, identity: Unkeyed }))
    .then(receiveSubmission({ ...request, identity: Unkeyed }))
    .then(sendSubmission({ ...request, identity: Unkeyed }))
    .then(receiveSubmission({ ...request, identity: Unkeyed }))
    .expect(normalSafety).expect(usage.entries.length() == 2)

  run concurrentDefinitionFirstWinsTest = normalInit
    .then(sendSubmission(request))
    .then(sendSubmission({ ...request, definition: { ...definition, input: 2 } }))
    .then(receiveSubmission(request))
    .then(receiveSubmission({ ...request, definition: { ...definition, input: 2 } }))
    .expect(normalSafety).expect(focused(usage).request == request and identityConflictWitness)

  run concurrentDefinitionReverseWinsTest = normalInit
    .then(sendSubmission(request))
    .then(sendSubmission({ ...request, definition: { ...definition, input: 2 } }))
    .then(receiveSubmission({ ...request, definition: { ...definition, input: 2 } }))
    .then(receiveSubmission(request)).expect(normalSafety)
    .expect(focused(usage).request.definition.input == 2 and identityConflictWitness)

  run closedSubmissionReturnsBusinessValueTest = succeededInit.expect(normalSafety)
    .then(loseSubmissionReply).then(normalCrashCoordinator).then(normalRestartCoordinator)
    .then(sendSubmission(request)).then(receiveSubmission(request)).then(readFacts)
    .expect(normalSafety).expect(usage.entries.length() == 1 and external.invocations.length() == 1)
    .expect(usage.replies.contains({ request: request,
      result: ExistingIntent({ id: 1, outcomes: List({ kind: OutcomeSucceeded, exec: Current(1), value: 1 }) }) }))

  run lateDifferentSuccessValuePreservedTest = succeededInit
    .then(normalReceiveConflict({ ...completionReport(external, t1), value: 2 }))
    .expect(normalSafety).expect(authority.durable.reports.size() == 2)
    .expect(authority.durable.attempts.get(1).conflict)
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, exec: Current(1), value: 1 }))

  // Defensive trusted-ingress fixture: two authenticated reports disagree in content.
  // It changes only transport, not the ledger or external result.
  action normalReceiveConflict(r: Report): bool = all {
    network' = network.union(Set(ResultReport(r))), authority' = authority, workers' = workers,
    external' = external, clock' = clock, usage' = usage,
  }.then(normalReceive(r))

  run unknownFactsReadableAfterRestartTest = preparedInit.then(normalAuthorize(t1, syncHandler))
    .then(normalClock(2)).then(normalExpire(1)).then(normalCrashCoordinator).then(normalRestartCoordinator)
    .then(readFacts).then(discoverWork).expect(normalSafety)
    .expect(authority.durable.attempts.get(1).phase == Unknown)
    .expect(authority.durable.phase == Open and authority.durable.outcomes.length() == 0)
    .expect(discoveryWitness and usage.reads.length() == 1)

  run alternateWorkerHealthyPathTest = submittedInit.then(normalCreate(1)).then(normalClaim(1, 2))
    .then(normalRequest(tokenFor(authority.durable, 1)))
    .then(normalAuthorize(tokenFor(authority.durable, 1), syncHandler))
    .then(normalGrant(tokenFor(authority.durable, 1))).then(normalCall(tokenFor(authority.durable, 1)))
    .then(normalComplete(1, Success, 2)).then(normalPublish(tokenFor(authority.durable, 1)))
    .then(normalReceive(completionReport(external, tokenFor(authority.durable, 1)))).expect(normalSafety)
    .expect(external.invocations.nth(0).token.worker == 2 and succeededReached)

  run preparedWorkRediscoveredTest = submittedInit.then(normalCreate(1))
    .then(normalCrashCoordinator).then(normalRestartCoordinator).then(discoverWork)
    .expect(normalSafety).expect(usage.discovered == Set(1))
}
