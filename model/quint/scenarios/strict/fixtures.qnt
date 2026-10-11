// One shared unbound core instance and legal shared prefixes; scenario groups reuse this state.
module strictFixtures {

  import beamletCore.* from "../../beamletCore"
  export beamletCore.*

  pure val t1: Token = { exec: 1, worker: 1, incarnation: 1, generation: 1 }

  pure val reclaimed: Token = { exec: 1, worker: 2, incarnation: 1, generation: 2 }

  pure val success1: Report = { id: 2, exec: 1, kind: Success, origin: ByWorker(t1) }

  pure val failure1: Report = { ...success1, kind: Failure }

  pure val notFound1: Report = { id: 3, exec: 1, kind: NotFound, origin: ByQuery }

  action preparedInit = init.expect(safety)
    .then(createExecution(1)).expect(safety)
    .then(claimExecution(1, 1)).expect(safety)

  action grantedInit = preparedInit
    .then(requestStart(t1)).expect(safety)
    .then(authorizeStart(t1)).expect(safety)

  action runningInit = grantedInit
    .then(receiveGrant(t1)).expect(safety)
    .then(callExternal(t1)).expect(safety)
}
