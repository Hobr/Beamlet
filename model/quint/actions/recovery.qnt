// Frame-complete replacement, clock, fault and terminal transitions.
module coreActionsRecovery {
  import coreLogicOutcomes.* from "../logic/outcomes"
  export coreLogicOutcomes.*
  import coreLogicRecovery.* from "../logic/recovery"
  export coreLogicRecovery.*

  action moveClockTo(nextTime: int): bool = all {
    CLOCK_VALUES.contains(nextTime), nextTime != clock,
    authority' = authority, workers' = workers, network' = network,
    external' = applyClockMove(external, clock, nextTime), clock' = nextTime,
  }

  action moveClock = {
    nondet nextTime = CLOCK_VALUES.exclude(Set(clock)).oneOf()
    moveClockTo(nextTime)
  }

  action cancelIntent = {
    val outcome: Outcome = { kind: OutcomeCancelled, exec: NoCurrent }
    all {
      authority.online, canCommit(authority.durable, outcome),
      authority' = { ...authority, durable: applyCommit(authority.durable, outcome) },
      workers' = workers, network' = network, external' = external, clock' = clock,
    }
  }

  action finishFailure(e: int): bool = {
    val outcome: Outcome = { kind: OutcomeFailed, exec: Current(e) }
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
