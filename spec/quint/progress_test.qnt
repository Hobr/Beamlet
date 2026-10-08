module progress_test {
  import architectureProgressAnalysis.* from "./architecture"
  run conditionalSchedulerEnvelopeTest = progressInit.expect(conditionalSafety)
    .then(progressStep).expect(conditionalSafety).then(progressStep).expect(conditionalSafety)
    .then(progressStep).expect(conditionalSafety).then(progressStep).expect(conditionalSafety)
    .then(progressStep).expect(conditionalSafety).then(progressStep).expect(conditionalSafety)
    .then(progressStep).expect(conditionalSafety).then(progressStep).expect(conditionalSafety)
    .expect(progressEnvelopeComplete)
}
