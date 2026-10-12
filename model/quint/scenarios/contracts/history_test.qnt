module historyScenarios {
  import historyProtocol.* from "../../contracts/history"
  export historyProtocol.*
  pure val historySuccess: Report = { id: 2, exec: 1, kind: Success, value: 0, origin: ByWorker(historyToken) }
  action historyCompletedInit = historyRunningInit.then(all { completeAtResource(1, Success), holdHistory })
    .then(all { publishCompletion(historyToken), holdHistory })
    .then(historyCommand(1, HistoryReport(historySuccess)))
  run healthySchedulerHandlesUnclaimedLeaseTest = historyInit.then(historyHealthyStep).expect(historySafety)
  run draftIsInvisibleTest = historyInit.then(prepareHistory(1, HistoryCreate)).expect(historySafety)
    .expect(not(authority.durable.attempts.get(1).exists) and historyStore.groups.length() == 0)
  run rollbackLeavesNoStateOrHistoryTest = historyInit.then(prepareHistory(1, HistoryCreate))
    .then(rollbackHistory(1)).expect(historySafety and historyRollbackWitness)
    .expect(authority.durable == initialLedger and historyStore.groups.length() == 0)
  run crashDiscardsOnlyUncommittedDraftTest = historyPreparedInit.then(prepareHistory(1, HistoryAuthorize))
    .then(crashHistoryCoordinator).then(all { restartCoordinator, holdHistory })
    .expect(historySafety and historyRollbackWitness)
    .expect(historyDrafts.get(1) == NoHistoryDraft and historyStore.groups.length() == 2)
  run outcomeAndEvidenceShareCommitGroupTest = historyCompletedInit.expect(historySafety and historyOutcomeWitness)
    .expect(historyStore.groups.length() == 4)
    .expect(historyStore.groups.nth(3).events == List({ kind: EvidenceStored, exec: Current(1) },
      { kind: OutcomeStored, exec: Current(1) }))
  run competingDraftsCannotOverwriteFirstCommitTest = historyInit
    .then(prepareHistory(1, HistoryCreate)).then(prepareHistory(2, HistoryCreate)).then(commitHistory(1))
    .expect(historySafety).then(commitHistory(2).fail())
  run staleDraftCanRollbackAndReReadTest = historyInit
    .then(prepareHistory(1, HistoryCreate)).then(prepareHistory(2, HistoryCreate)).then(commitHistory(1))
    .then(rollbackHistory(2)).then(historyCommand(2, HistoryClaim))
    .expect(historySafety and historyStore.groups.nth(1).actor == 2)
  run clockRollbackDoesNotReorderCommittedGroupsTest = historyInit.then(all { moveClockTo(2), holdHistory })
    .then(historyCommand(1, HistoryCreate)).then(all { moveClockTo(0), holdHistory })
    .then(historyCommand(2, HistoryClaim)).expect(historySafety)
    .expect(historyStore.groups.nth(0).at == 2 and historyStore.groups.nth(1).at == 0)
    .expect(historyStore.groups.nth(1).sequence == 2)
  run expiredAuthorizationDraftCannotCommitTest = historyPreparedInit.then(prepareHistory(1, HistoryAuthorize))
    .then(all { moveClockTo(2), holdHistory }).expect(historySafety).then(commitHistory(1).fail())
  run reportReplayDoesNotCreateAnotherHistoryGroupTest = historyCompletedInit
    .then(all { loseMessage(StoredReceipt(historySuccess)), holdHistory }).then(historyDuplicate(historySuccess))
    .expect(historySafety and historyDuplicateWitness and historyStore.groups.length() == 4)
  run savedGroupSurvivesCoordinatorRestartTest = historyCompletedInit.then(crashHistoryCoordinator)
    .then(all { restartCoordinator, holdHistory }).expect(historySafety and historyOutcomeWitness)
    .expect(historyStore.groups.length() == 4)
}
