module recovery_test {
  import recovery.* from "./recovery"
  run conditionalRecoveryTest = init.expect(safety and not(recovered))
    .then(14.reps(_ => step.expect(safety))).expect(recovered and rank == 0)
}
