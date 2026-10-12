module sharedMutations {
  import sharedScenarios.* from "../scenarios/contracts/shared_test"
  export sharedScenarios.*
  const BUG: int
  action mutantInit = if (BUG == 1 or BUG == 3) sharedAppliedInit else sharedBothInit
  action mutantStep = if (BUG == 1) {
    val second: ObjectReceipt = { request: objectRequest(2), applied: true, version: 2, value: 1 }
    all { holdRuntime, callerRounds' = callerRounds, agentLocals' = agentLocals,
      sharedObject' = { ...sharedObject, version: 2, content: 2, receipts: sharedObject.receipts.union(Set(second)),
        writes: sharedObject.writes.append(second) } }
  } else {
    val d = multiStore.intents.get(2)
    // Borrow A's receipt, or infer B completed merely because the object now contains A's content.
    val wrong: Report = { id: 3, exec: 1, kind: Success, value: 1, origin: ByQuery }
    all { writeIntent(2, { ...d, ledger: recordAndMaybeCommit(d.ledger, wrong) },
      sharedWorkers, resources.get(2), multiNetwork.messages), holdObject }
  }
  val mutantInvariant = if (BUG == 1) objectWritesSound else objectEvidenceSound
  run mutationCaughtTest = mutantInit.expect(sharedSafety).then(mutantStep).expect(not(mutantInvariant))
}
