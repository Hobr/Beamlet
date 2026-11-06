use beamlet_kernel::{
    id::{AttemptId, OperationId, ReportId, RoleInstanceId},
    model::{Effect, ExecutionResult, Operation, SubmitReport},
    state::{RuleError, WorkerPhase},
};

#[test]
fn identities_preserve_bits_without_uuid_or_serialization_dependencies() {
    let raw = 0x00112233445566778899aabbccddeeff;
    assert_eq!(OperationId::from_u128(raw).as_u128(), raw);
    assert_eq!(AttemptId::from(raw).as_u128(), raw);
    assert_eq!(ReportId::from(raw).as_u128(), raw);
    assert_eq!(RoleInstanceId::from(raw).as_u128(), raw);
    assert_eq!(
        OperationId::from(raw).to_string(),
        "00112233-4455-6677-8899-aabbccddeeff"
    );
}

fn evidence(effect: Effect, result: ExecutionResult<u8, u8>) -> SubmitReport<u8, u8> {
    SubmitReport {
        report_id: 1.into(),
        operation_id: 2.into(),
        attempt_id: 3.into(),
        effect,
        result,
    }
}

#[test]
fn failure_does_not_infer_effects_and_rejection_requires_none() {
    for effect in [Effect::None, Effect::Observed, Effect::Unknown] {
        assert!(
            evidence(effect, ExecutionResult::Failed { error: 7 })
                .validate()
                .is_ok()
        );
    }
    assert!(
        evidence(Effect::None, ExecutionResult::Rejected { error: 7 })
            .validate()
            .is_ok()
    );
    for effect in [Effect::Observed, Effect::Unknown] {
        assert_eq!(
            evidence(effect, ExecutionResult::Rejected { error: 7 }).validate(),
            Err(RuleError::InvalidRejectionEffect)
        );
    }
}

#[test]
fn completion_rule_distinguishes_rejection_from_execution() {
    let succeeded = ExecutionResult::<u8, u8>::Succeeded { output: 1 };
    let failed = ExecutionResult::<u8, u8>::Failed { error: 2 };
    let rejected = ExecutionResult::<u8, u8>::Rejected { error: 3 };
    assert_eq!(
        WorkerPhase::Queued.finish(&rejected),
        Ok(WorkerPhase::Completed)
    );
    assert_eq!(
        WorkerPhase::Running.finish(&succeeded),
        Ok(WorkerPhase::Completed)
    );
    assert_eq!(
        WorkerPhase::Running.finish(&failed),
        Ok(WorkerPhase::Completed)
    );
    assert_eq!(
        WorkerPhase::Queued.finish(&succeeded),
        Err(RuleError::InvalidTransition)
    );
    assert_eq!(
        WorkerPhase::Running.finish(&rejected),
        Err(RuleError::InvalidTransition)
    );
    assert_eq!(
        WorkerPhase::Completed.finish(&succeeded),
        Err(RuleError::InvalidTransition)
    );
}

#[test]
fn operation_definition_can_be_an_ordinary_non_serializable_value() {
    #[derive(Debug, Eq, PartialEq)]
    struct Input {
        amount: u32,
    }
    let operation = Operation {
        operation_id: 9.into(),
        task: Input { amount: 42 },
    };
    assert_eq!(operation.task.amount, 42);
}
