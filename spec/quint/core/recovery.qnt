// Conditional recovery schedule over one instance of the unchanged core actions.
// Premises: writes remain available; Run stays active/open until valid finish;
// owner1 remains alive/compatible and completes successfully; no new input,
// takeover, suspension or fault; explicit repeat decision is supplied and each
// next scheduled enabled action is eventually selected. This is NOT core.step.
module recovery {
  import core(RUNS = Set(0), QUEUE_LIMIT = 4) as C from "./model"
  // This monitor belongs only to the projection; no business state is added.
  var previousRank: int
  val rank = {
    val c = C::control.get(0)
    val e = C::effect.get(0)
    val first = C::attempt.get((0, 0))
    val recoveryAttempt = C::attempt.get((0, 1))
    if (c.life == C::Finished) 0
    else if (not(e.exists)) (if (C::held.get(0).valid) 14 else 15)
    else if (first.knowledge == C::Unused) 13
    else if (first.entries == 0) 12
    else if (first.evidence == C::NoEvidence) (if (C::owner.get(0).reachable) 11 else 10)
    else if (recoveryAttempt.knowledge == C::Unused) (if (e.permit == 0) 9 else 8)
    else if (recoveryAttempt.entries == 0) 7
    else if (recoveryAttempt.actual == C::NoActual) 6
    else if (recoveryAttempt.evidence == C::NoEvidence) 5
    else if (C::queueHead(0).kind == C::Uncertainty) 4
    else if (not(C::held.get(0).valid)) 3
    else 2
  }
  action init = all {C::init, previousRank' = 16}
  action step = all {
    previousRank' = rank,
    any {
      all {rank == 15, C::evaluate(0, C::Invoke, false, true)},
      all {rank == 14, C::commit(0)},
      all {rank == 13, C::admit(0, 0, 0)},
      all {rank == 12, C::enter(0, 0, 0)},
      all {rank == 11, C::disconnect(0, false)},
      all {rank == 10, C::lose(0, 0)},
      all {rank == 9, C::repeat(0)},
      all {rank == 8, C::admit(0, 1, 1)},
      all {rank == 7, C::enter(0, 1, 1)},
      all {rank == 6, C::complete(0, 1, C::Succeeded)},
      all {rank == 5, C::record(0, 1)},
      all {rank == 4, C::dispose(0)},
      all {rank == 3, C::evaluate(0, C::Finish, false, true)},
      all {rank == 2, C::commit(0)},
    },
  }
  val rankDecreases = rank >= 0 and rank < previousRank
  val premises = C::writes and C::control.get(0).active and C::owner.get(1).alive
  val safety = C::safety and premises and rankDecreases
  val recovered = C::effect.get(0).phase == C::Consumed and C::control.get(0).life == C::Finished
}
