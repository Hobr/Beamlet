// One shared unbound core instance and legal shared prefixes; scenario groups reuse this state.
module fencedFixtures {

  import beamletExecution.* from "../../beamletExecution"
  export beamletExecution.*

  pure val t1: Token = { exec: 1, worker: 1, incarnation: 1, generation: 1 }

  pure val t2: Token = { exec: 2, worker: 2, incarnation: 1, generation: 1 }

  pure val excluded1: Report = { id: 3, exec: 1, kind: NotExecuted, value: 0, origin: ByQuery }

  pure val success2: Report = { id: 2, exec: 2, kind: Success, value: 0, origin: ByWorker(t2) }

  // Worker 已持有许可但尚未调用,是资源排除旧尝试未来执行的关键窗口.
  // 具体入口绑定 CAN_FENCE=true;必须先可靠排除,再允许替代,不依赖 lease 到期猜测安全.
  action grantHeldInit = init.expect(safety)
    .then(createExecution(1)).expect(safety)
    .then(claimExecution(1, 1)).expect(safety)
    .then(requestStart(t1)).expect(safety)
    .then(authorizeStart(t1)).expect(safety)
    .then(receiveGrant(t1)).expect(safety)
}
