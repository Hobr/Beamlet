// Unbound scenario aggregation: all groups share one state instance.
module repeatingScenarios {
  import repeatingCommandsTests.* from "./commands_test"
  export repeatingCommandsTests.*
  import repeatingRejectionsTests.* from "./rejections_test"
  export repeatingRejectionsTests.*
  import repeatingAccessTests.* from "./access_test"
  export repeatingAccessTests.*
  import repeatingCommandQualificationTests.* from "./command_qualification_test"
  export repeatingCommandQualificationTests.*
  import repeatingRevisionTests.* from "./revision_test"
  export repeatingRevisionTests.*
  import repeatingReconciliationTests.* from "./reconciliation_test"
  export repeatingReconciliationTests.*
  import repeatingRuleTests.* from "./rules_test"
  export repeatingRuleTests.*
  import repeatingRecoveryTests.* from "./recovery_test"
  export repeatingRecoveryTests.*
}
