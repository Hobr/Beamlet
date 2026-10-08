module composition {
  import core(RUNS = Set(0, 1), QUEUE_LIMIT = 6) as C from "./model"
  action init = C::init
  action step = C::step
  val safety = C::safety
  val intentWitness = C::intentWitness
  val entryWitness = C::entryWitness
  val unknownWitness = C::unknownWitness
  val recoveryWitness = C::recoveryWitness
  val consumedWitness = C::consumedWitness
  val recoveryConsumedWitness = C::recoveryConsumedWitness
  val inconclusiveWitness = C::inconclusiveWitness
  val failedUnknownWitness = C::failedUnknownWitness
  val failedReplyWitness = C::failedReplyWitness
  val branchWorkWitness = C::branchWorkWitness
}
