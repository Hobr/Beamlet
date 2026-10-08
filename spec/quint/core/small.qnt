module small {
  import core(RUNS = Set(0), QUEUE_LIMIT = 4) as C from "./model"
  action init = C::init
  action step = C::step
  val safety = C::safety
}
