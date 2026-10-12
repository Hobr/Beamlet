// Frame-complete replacement, clock, fault and terminal transitions.
module coreActionsRecovery {
  import coreLogicOutcomes.* from "../logic/outcomes"
  export coreLogicOutcomes.*
  import coreLogicRecovery.* from "../logic/recovery"
  export coreLogicRecovery.*

  // 允许墙钟双向跳变以暴露仅凭 now < expiresAt"复活"旧租约的错误.
  action moveClockTo(nextTime: int): bool = all {
    CLOCK_VALUES.contains(nextTime), nextTime != clock,
    authority' = authority, workers' = workers, network' = network,
    external' = applyClockMove(external, clock, nextTime), clock' = nextTime,
  }

  action moveClock = {
    nondet nextTime = CLOCK_VALUES.exclude(Set(clock)).oneOf()
    moveClockTo(nextTime)
  }

  // 取消争夺唯一 Outcome,不保证外部效果停止;已发许可和迟到报告仍可继续处理.
  action cancelIntent = {
    val outcome: Outcome = { kind: OutcomeCancelled, value: 0, exec: NoCurrent }
    all {
      authority.online, canCommit(authority.durable, outcome),
      authority' = { ...authority, durable: applyCommit(authority.durable, outcome) },
      workers' = workers, network' = network, external' = external, clock' = clock,
    }
  }

  // 已知 Failure 只是事实;这个动作抽象策略决定不再尝试,仍须满足普通终结资格.
  action finishFailure(e: int): bool = {
    val outcome: Outcome = { kind: OutcomeFailed, value: knownResultValue(authority.durable, e, Failure), exec: Current(e) }
    all {
      authority.online, canCommit(authority.durable, outcome),
      authority' = { ...authority, durable: applyCommit(authority.durable, outcome) },
      workers' = workers, network' = network, external' = external, clock' = clock,
    }
  }

  action replaceExecution(oldExec: int, newExec: int): bool = all {
    authority.online, canReplace(authority.durable, oldExec, newExec),
    authority' = { ...authority, durable: applyReplace(authority.durable, oldExec, newExec) },
    workers' = workers, network' = network, external' = external, clock' = clock,
  }

  // 数据库已提交状态按前提持久保留;此故障模型只停用 Authority 动作,不模拟 WAL/掉电恢复.
  action crashCoordinator = all {
    authority.online, authority' = { ...authority, online: false },
    workers' = workers, network' = network,
    external' = { ...external, marks: external.marks.union(Set("coordinatorCrashed")) }, clock' = clock,
  }

  action restartCoordinator = all {
    not(authority.online), authority' = { ...authority, online: true },
    workers' = workers, network' = network,
    external' = { ...external, marks: external.marks.union(Set("coordinatorRestarted")) }, clock' = clock,
  }

  action loseMessage(m: Message): bool = all {
    network.contains(m), authority' = authority, workers' = workers,
    network' = network.exclude(Set(m)),
    external' = { ...external, marks: external.marks.union(Set("messageLost")) }, clock' = clock,
  }

  action loseAnyMessage = all {
    network.size() > 0,
    nondet m = network.oneOf()
    loseMessage(m),
  }
}
