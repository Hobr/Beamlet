// Checks recompute source facts and original identity, rather than trusting a saved flag.
module continuationProperties {
  import continuationActions.* from "./actions"
  export continuationActions.*
  val decisionSourcesSound = match progress.decision {
    | NoProgress => true
    | ProgressCommitted(r) => sourceQualified(callerRounds, multiStore, r)
  }
  val decisionStable = progress.commits.length() <= 1 and
    (if (progress.commits.length() == 0) progress.decision == NoProgress
      else progress.decision == ProgressCommitted(progress.commits.nth(0)))
  val nextManifestSound = not(callerRounds.get(2).exists) or match progress.decision {
    | NoProgress => false
    | ProgressCommitted(r) => manifestMatches(callerRounds, r)
  }
  val dispatchOrdering = multiNetwork.requests.forall(envelope =>
      requestReady(progress, callerRounds, envelope.request))
    and multiNetwork.replies.forall(envelope => requestReady(progress, callerRounds, envelope.reply.request))
    and multiStore.catalog.indices().forall(index =>
      requestReady(progress, callerRounds, multiStore.catalog.nth(index).request))
  val continuationSafety = multiSafety and decisionSourcesSound and decisionStable
    and nextManifestSound and dispatchOrdering
  val decisionWitness = progress.commits.length() == 1
  val partialDecisionWitness = decisionWitness and not(callerRounds.get(1).completed)
    and INTENTS.exists(i => i <= 2 and multiStore.intents.get(i).ledger.phase == Open)
  val manifestWitness = callerRounds.get(2).exists
  val successorSubmittedWitness = multiStore.catalog.length() == 3
  val partialSubmissionWitness = successorSubmittedWitness
    and INTENTS.exists(i => i <= 2 and multiStore.intents.get(i).ledger.phase == Open)
  val recoveredManifestWitness = manifestWitness and progress.registrations.indices()
    .exists(i => progress.registrations.nth(i) > 0)
  val recoveredReadWitness = progress.recoveredReads.exists(r => r.call == 2)
  val recoveredSuccessorWitness = callerRounds.get(2).completed and progress.collections.indices()
    .exists(i => progress.collections.nth(i).call == 2 and progress.collections.nth(i).restarts > 0)
  val successorCompletedWitness = callerRounds.get(2).completed
}
