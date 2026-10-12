module claimMutations {
  import claimScenarios.* from "../scenarios/contracts/claim_test"
  export claimScenarios.*
  const BUG: int
  action mutantInit = if (BUG == 3) claimCommittedInit.then(all { crashWorker(1), holdClaims })
      .then(all { restartWorker(1), holdClaims })
    else claimLostInit
  action mutantStep = if (BUG == 1) {
    val l = applyClaim(authority.durable, 1, 1, 1, clock)
    val second: ClaimReply = { request: r1, token: tokenFor(l, 1) }
    all { authority' = { ...authority, durable: l }, workers' = workers, network' = network,
      external' = external, clock' = clock, claimJournal' = claimJournal.union(Set(second)),
      claimWire' = { ...claimWire, replies: claimWire.replies.union(Set(second)) } }
  } else if (BUG == 2) all {
    holdCore, claimJournal' = claimJournal,
    claimWire' = { ...claimWire, replies: claimWire.replies.union(Set({ ...a1, token: { ...a1.token, worker: 2 } })) },
  } else all {
    authority' = authority, network' = network, external' = external, clock' = clock,
    claimJournal' = claimJournal, claimWire' = claimWire,
    workers' = workers.set(1, { ...workers.get(1), leases: Set(a1.token) }),
  }
  val mutantInvariant = if (BUG == 1) allocationSound else if (BUG == 2) claimDeliverySound else claimSessionsSound
  run mutationCaughtTest = mutantInit.expect(claimSafety and claimSessionsSound)
    .then(mutantStep).expect(not(mutantInvariant))
}
