use beamlet_agent::{
    Admission, Agent, AgentError, ExecutorError, Limits, OperationPhase, StateError, WaitStatus,
    id::{AttemptId, OperationId},
    model::{DispatchAttempt, Effect, ExecutionResult, Message, Operation, SubmitReport},
};
use std::time::Duration;

#[derive(Clone, Debug, Eq, PartialEq)]
struct Input(u32);

fn operation(id: u128, value: u32) -> Operation<Input> {
    Operation {
        operation_id: id.into(),
        task: Input(value),
    }
}
fn agent(limits: Limits) -> Agent<Input, u64, &'static str> {
    Agent::new(2.into(), vec![3.into(), 4.into()], limits).unwrap()
}
async fn execute(attempt: DispatchAttempt<Input>) -> SubmitReport<u64, &'static str> {
    SubmitReport {
        report_id: (1000 + attempt.attempt_id.as_u128()).into(),
        operation_id: attempt.operation.operation_id,
        attempt_id: attempt.attempt_id,
        effect: Effect::None,
        result: ExecutionResult::Succeeded {
            output: u64::from(attempt.operation.task.0) * 2,
        },
    }
}

#[tokio::test]
async fn application_intents_use_one_authorization_and_query_their_own_results() {
    let mut agent = agent(Limits::default());
    let first = agent.submit(operation(1, 21), 1.into()).unwrap();
    assert_eq!(first.admission, Admission::New);
    let duplicate = agent.submit(operation(1, 21), 99.into()).unwrap();
    assert_eq!(duplicate.admission, Admission::Duplicate);
    assert_eq!(first.dispatch, duplicate.dispatch);
    assert!(matches!(
        agent.submit(operation(1, 22), 3.into()),
        Err(AgentError::State(StateError::OperationConflict))
    ));
    agent.submit(operation(2, 7), 2.into()).unwrap();
    let mut received = Vec::new();
    while let Some(delivery) = agent.next_report(execute).await.unwrap() {
        let Message::SubmitReport(report) = delivery.message else {
            panic!("expected a report");
        };
        received.push((report.operation_id.as_u128(), report.result));
    }
    received.sort_by_key(|value| value.0);
    assert_eq!(
        received,
        vec![
            (1, ExecutionResult::Succeeded { output: 42 }),
            (2, ExecutionResult::Succeeded { output: 14 }),
        ]
    );
    for id in [1, 2] {
        let view = agent.operation(id.into()).unwrap();
        assert_eq!(view.phase, OperationPhase::Reported);
        let retained = agent.report(view.adopted_report.unwrap()).unwrap();
        assert!(
            matches!(&retained.message, Message::SubmitReport(report) if report.operation_id == OperationId::from(id))
        );
    }
}

#[tokio::test(start_paused = true)]
async fn cancelled_agent_wait_keeps_the_original_execution_and_adopts_late_evidence() {
    let mut agent = agent(Limits::default());
    agent.submit(operation(1, 21), 1.into()).unwrap();
    async fn delayed(attempt: DispatchAttempt<Input>) -> SubmitReport<u64, &'static str> {
        tokio::time::sleep(Duration::from_millis(100)).await;
        execute(attempt).await
    }
    let started = tokio::time::Instant::now();
    assert!(
        tokio::time::timeout(Duration::from_millis(10), agent.next_report(delayed))
            .await
            .is_err()
    );
    agent.mark_wait_timeout(1.into()).unwrap();
    let duplicate = agent.submit(operation(1, 21), 99.into()).unwrap();
    assert_eq!(duplicate.admission, Admission::Duplicate);
    let late = agent.next_report(delayed).await.unwrap().unwrap();
    assert_eq!(started.elapsed(), Duration::from_millis(100));
    assert!(
        matches!(late.message, Message::SubmitReport(report) if report.attempt_id == AttemptId::from(1))
    );
    let view = agent.operation(1.into()).unwrap();
    assert_eq!(view.phase, OperationPhase::Reported);
    assert_eq!(view.wait_status, WaitStatus::TimedOut);
    assert!(agent.next_report(delayed).await.unwrap().is_none());
}

#[tokio::test]
async fn worker_refusal_retains_authority_acceptance_without_automatic_redelivery() {
    let limits = Limits {
        queue_capacity: 1,
        ..Limits::default()
    };
    let mut agent =
        Agent::<Input, u64, &'static str>::new(2.into(), vec![3.into()], limits).unwrap();
    agent.submit(operation(1, 21), 1.into()).unwrap();
    assert!(matches!(
        agent.submit(operation(2, 7), 2.into()),
        Err(AgentError::State(StateError::QueueFull))
    ));
    assert_eq!(
        agent.operation(2.into()).unwrap().phase,
        OperationPhase::Accepted
    );
    assert_eq!(
        agent.submit(operation(2, 7), 99.into()).unwrap().admission,
        Admission::Duplicate
    );
    agent.next_report(execute).await.unwrap().unwrap();
    assert!(agent.next_report(execute).await.unwrap().is_none());
    let view = agent.operation(2.into()).unwrap();
    assert_eq!(view.phase, OperationPhase::Accepted);
    assert!(view.adopted_report.is_none());
    assert!(
        matches!(&view.dispatch.message, Message::DispatchAttempt(attempt) if attempt.attempt_id == AttemptId::from(2))
    );
}

#[tokio::test]
async fn invalid_executor_evidence_is_not_turned_into_an_ordinary_failure() {
    let mut agent = agent(Limits::default());
    agent.submit(operation(1, 21), 1.into()).unwrap();
    async fn incorrect(attempt: DispatchAttempt<Input>) -> SubmitReport<u64, &'static str> {
        let mut report = execute(attempt).await;
        report.operation_id = 99.into();
        report
    }
    assert!(matches!(
        agent.next_report(incorrect).await,
        Err(AgentError::Executor(ExecutorError::State(
            StateError::InvalidBinding
        )))
    ));
    let view = agent.operation(1.into()).unwrap();
    assert_eq!(view.phase, OperationPhase::Dispatched);
    assert!(view.adopted_report.is_none());
}
