// Controlled mistakes start from legal normal-use prefixes and never enter normalStep.
module normalUseMutations {
  import normalUseProfile.* from "../beamletNormalUse"
  export normalUseProfile.*
  const BUG: int

  action mutantInit = if (BUG == 1 or BUG == 5) callbackRunningInit
    .then(normalComplete(1, Success, 1)).then(normalPublish(t1))
    else if (BUG == 2) submittedInit
    else if (BUG == 3 or BUG == 6) callbackRunningInit
    else if (BUG == 4) retryPendingInit.then(normalClock(4))
    else preparedInit.then(normalAuthorize(t1, syncHandler)).then(normalGrant(t1)).then(normalCall(t1))
      .then(normalComplete(1, Failure, 2)).then(normalPublish(t1))

  action mutantStep = if (BUG == 1) {
    val r = completionReport(external, t1)
    val recorded = recordAndMaybeCommit(authority.durable, r)
    val wrong: Outcome = { kind: OutcomeSucceeded, exec: Current(1), value: 9 }
    all {
      authority' = { ...authority, durable: { ...recorded, outcomes: List(wrong), firstOutcome: List(wrong),
        commits: recorded.commits.foldl(List(), (xs, w) => xs.append({ ...w, outcome: wrong })) } },
      usage' = usage, workers' = workers, network' = network, external' = external, clock' = clock,
    }
  } else if (BUG == 2) all {
    usage' = { ...usage, entries: usage.entries.foldl(List(), (xs, e) => xs.append({ ...e,
      request: { ...e.request, definition: { ...e.request.definition, input: 9 } } })) },
    authority' = authority, workers' = workers, network' = network, external' = external, clock' = clock,
  } else if (BUG == 3) all {
    authority' = { ...authority, durable: { ...authority.durable,
      attempts: authority.durable.attempts.set(1, { ...authority.durable.attempts.get(1), completion: NoCompletion }) } },
    usage' = usage, workers' = workers, network' = network, external' = external, clock' = clock,
  } else if (BUG == 4) all {
    authority' = { ...authority, durable: applyReplaceWithEvidence(authority.durable, 1, 2, true) },
    usage' = { ...usage, retries: usage.retries.append({ oldExec: 1, newExec: 2,
      binding: usage.bindings.get(1), at: clock, repeatAccepted: false, before: authority.durable,
      definition: focused(usage).request.definition, context: focused(usage).context }) },
    workers' = workers, network' = network, external' = external, clock' = clock,
  } else if (BUG == 5) {
    val r = completionReport(external, t1)
    val before = authority.durable
    val recorded = applyReport(before, r)
    all {
      authority' = { ...authority, durable: recorded },
      usage' = { ...usage, acceptances: usage.acceptances.append({ report: r, before: before, after: recorded, stop: true, definition: focused(usage).request.definition }) },
      workers' = workers, network' = network, external' = external, clock' = clock,
    }
  } else if (BUG == 6) all {
    usage' = { ...usage, bindings: usage.bindings.set(1, BoundHandler({
      handler: callbackHandler, definition: definition, context: 9 })) },
    authority' = authority, workers' = workers, network' = network, external' = external, clock' = clock,
  } else {
    val r = completionReport(external, t1)
    val before = authority.durable
    val recorded = applyReport(before, r)
    all {
      authority' = { ...authority, durable: recorded },
      usage' = { ...usage, acceptances: usage.acceptances.append({ report: r, before: before, after: recorded, stop: false, definition: focused(usage).request.definition }) },
      workers' = workers, network' = network, external' = external, clock' = clock,
    }
  }
  val mutantInvariant = normalSafety
  run mutationCaughtTest = mutantInit.expect(normalSafety).then(mutantStep).expect(not(mutantInvariant))
}
