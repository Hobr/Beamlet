// One shared unbound core instance and legal shared prefixes; scenario groups reuse this state.
module fencedFixtures {

  import beamletCore.* from "../../beamletCore"
  export beamletCore.*

  pure val t1: Token = { exec: 1, worker: 1, incarnation: 1, generation: 1 }

  pure val t2: Token = { exec: 2, worker: 2, incarnation: 1, generation: 1 }

  pure val excluded1: Report = { id: 3, exec: 1, kind: NotExecuted, origin: ByQuery }

  pure val success2: Report = { id: 2, exec: 2, kind: Success, origin: ByWorker(t2) }

  action grantHeldInit = init.expect(safety)
    .then(createExecution(1)).expect(safety)
    .then(claimExecution(1, 1)).expect(safety)
    .then(requestStart(t1)).expect(safety)
    .then(authorizeStart(t1)).expect(safety)
    .then(receiveGrant(t1)).expect(safety)
}
