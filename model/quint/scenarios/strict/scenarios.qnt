// Unbound scenario aggregation: all groups share one state instance.
module strictScenarios {
  import strictLifecycleTests.* from "./lifecycle_test"
  export strictLifecycleTests.*
  import strictRecoveryTests.* from "./recovery_test"
  export strictRecoveryTests.*
  import strictConflictsTests.* from "./conflicts_test"
  export strictConflictsTests.*
  import strictQualificationTests.* from "./qualification_test"
  export strictQualificationTests.*
}
