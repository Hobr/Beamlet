module resourceScenarios {
  import resourceProtocol.* from "../../contracts/resource"
  export resourceProtocol.*
  run correctTargetCallsTest = resourceBoundInit.then(callResource(t1)).expect(resourceSafety and resourceCalledWitness)
  run wrongDeviceDoesNotAuthorizeTest = resourcePreparedInit
    .then(changeEnvironment(1, { ...target, device: 2 })).expect(resourceSafety)
    .then(authorizeResource(t1, syncHandler).fail())
  run wrongAccountDoesNotAuthorizeTest = resourcePreparedInit
    .then(changeEnvironment(1, { ...target, account: 2 })).expect(resourceSafety)
    .then(authorizeResource(t1, syncHandler).fail())
  run samePathDifferentObjectDoesNotAuthorizeTest = resourcePreparedInit
    .then(changeEnvironment(1, { ...target, object: 2 })).expect(resourceSafety)
    .then(authorizeResource(t1, syncHandler).fail())
  run accountChangesAfterAuthorizationBlockCallTest = resourceBoundInit
    .then(changeEnvironment(1, { ...target, account: 2 })).expect(resourceSafety).then(callResource(t1).fail())
  run protocolUpgradeCannotReplaceOriginalInterpretationTest = resourceBoundInit
    .then(changeEnvironment(1, { ...target, protocol: 2 })).expect(resourceSafety).then(callResource(t1).fail())
  run restoringExactTargetAllowsOriginalCallTest = resourceBoundInit
    .then(changeEnvironment(1, { ...target, object: 2 })).then(changeEnvironment(1, target))
    .then(callResource(t1)).expect(resourceSafety and resourceCalledWitness)
  run coordinatorRestartPreservesResourceBindingTest = resourceBoundInit
    .then(all { normalCrashCoordinator, holdResource }).then(all { normalRestartCoordinator, holdResource })
    .then(callResource(t1)).expect(resourceSafety and resourceCalledWitness)
  run incompatibleOperationReleaseDisabledTest = resourcePreparedInit.expect(resourceSafety)
    .then(authorizeResource(t1, { ...syncHandler, operation: 2 }).fail())
  run workerCanChangeWithoutChangingTargetTest = resourcePreparedInit
    .then(all { normalClock(2), holdResource }).then(all { normalClaim(1, 2), holdResource })
    .then(changeEnvironment(2, target)).then(all { normalClock(0), holdResource })
    .then(all { normalRequest({ ...t1, worker: 2, generation: 2 }), holdResource })
    .then(authorizeResource({ ...t1, worker: 2, generation: 2 }, syncHandler))
    .then(all { normalGrant({ ...t1, worker: 2, generation: 2 }), holdResource })
    .then(callResource({ ...t1, worker: 2, generation: 2 }))
    .expect(resourceSafety and migratedWorkerWitness)
  run newIncarnationDoesNotUseOldBindingToCallTest = resourceBoundInit
    .then(all { releaseWorker(1), holdResource }).then(all { normalRestartWorker(1), holdResource })
    .expect(resourceSafety).then(callResource(t1).fail())
}
