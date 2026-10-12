module historyMutations {
  import historyScenarios.* from "../scenarios/contracts/history_test"
  export historyScenarios.*
  const BUG: int
  action mutantInit = if (BUG == 1) historyRunningInit
    .then(all { completeAtResource(1, Success), holdHistory }).then(all { publishCompletion(historyToken), holdHistory })
    else historyCompletedInit
  action mutantStep = if (BUG == 1) all {
    authority' = { ...authority, durable: recordAndMaybeCommit(authority.durable, historySuccess) },
    workers' = workers, external' = external, network' = network, clock' = clock, holdHistory,
  } else {
    val group = if (BUG == 2) { ...historyStore.groups.nth(3), sequence: 1 }
      else { ...historyStore.groups.nth(3), sequence: 5, before: authority.durable,
        after: authority.durable, events: List() }
    val groups = if (BUG == 2) historyStore.groups.slice(0, 3).append(group)
      else historyStore.groups.append(group)
    all { authority' = authority, workers' = workers, network' = network, external' = external,
      clock' = clock, historyDrafts' = historyDrafts,
      historyStore' = { ...historyStore, groups: groups, committed: groups } }
  }
  val mutantInvariant = if (BUG == 1) historyStateAtomic else if (BUG == 2) historyGroupsSound else historyCommandsSound
  run mutationCaughtTest = mutantInit.expect(historySafety).then(mutantStep).expect(not(mutantInvariant))
}
