// One shared unbound core instance and legal shared prefixes; scenario groups reuse this state.
module strictFixtures {

  import beamletCore.* from "../../beamletCore"
  export beamletCore.*

  pure val t1: Token = { exec: 1, worker: 1, incarnation: 1, generation: 1 }

  pure val reclaimed: Token = { exec: 1, worker: 2, incarnation: 1, generation: 2 }

  pure val success1: Report = { id: 2, exec: 1, kind: Success, value: 0, origin: ByWorker(t1) }

  pure val failure1: Report = { ...success1, kind: Failure }

  pure val notFound1: Report = { id: 3, exec: 1, kind: NotFound, value: 0, origin: ByQuery }

  // 合法前缀逐步 expect(safety),避免直接捏造账本让测试从不可达状态开始.
  action preparedInit = init.expect(safety)
    .then(createExecution(1)).expect(safety)
    .then(claimExecution(1, 1)).expect(safety)

  // 已持久授权但 Worker 尚未收到许可,刻意留下取消/到期/丢回复的竞态窗口.
  action grantedInit = preparedInit
    .then(requestStart(t1)).expect(safety)
    .then(authorizeStart(t1)).expect(safety)

  // 已调用但资源尚未完成;完成,发布报告和 Authority 接收仍是后续独立步骤.
  action runningInit = grantedInit
    .then(receiveGrant(t1)).expect(safety)
    .then(callExternal(t1)).expect(safety)
}
