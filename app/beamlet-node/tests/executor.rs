use std::collections::{HashMap, HashSet};

use beamlet_node::{
    executor::WorkerExecutor,
    memory::{Authority, OperationPhase, ReportDisposition, StateError, WaitStatus, WorkerPhase},
    protocol::{
        AttemptId, Effect, Envelope, ExecutionResult, Limits, Message, OperationId, ProtocolError,
        RoleInstanceId, SubmitOperation, SubmitReport, TestTask,
    },
};
use serde_json::json;

fn node(id: u128) -> RoleInstanceId {
    id.into()
}

fn operation(id: u128) -> OperationId {
    id.into()
}

fn attempt(id: u128) -> AttemptId {
    id.into()
}

fn request(id: u128, task: TestTask) -> Envelope {
    Envelope::new(
        node(1),
        node(2),
        Message::SubmitOperation(SubmitOperation::new(operation(id), task)),
    )
}

fn authorized(id: u128, task: TestTask) -> Envelope {
    Authority::new(node(2), vec![node(3)], Limits::default())
        .unwrap()
        .submit(request(id, task), attempt(id))
        .unwrap()
        .dispatch
}

fn report(envelope: &Envelope) -> &SubmitReport {
    match &envelope.message {
        Message::SubmitReport(report) => report,
        other => panic!("expected SubmitReport, got {other:?}"),
    }
}

#[tokio::test]
async fn echo_runs_from_submission_to_authority_result() {
    let limits = Limits::default();
    let mut authority = Authority::new(node(2), vec![node(3)], limits).unwrap();
    let mut executor = WorkerExecutor::new(node(3), node(2), limits).unwrap();
    let accepted = authority
        .submit(
            request(
                1,
                TestTask::Echo(json!({"message": "你好", "items": [1, null, true]})),
            ),
            attempt(1),
        )
        .unwrap();

    executor.accept(accepted.dispatch).unwrap();
    authority.mark_dispatched(operation(1)).unwrap();
    assert_eq!(executor.start_ready(), 1);
    assert_eq!(
        executor.worker().phase(attempt(1)),
        Some(WorkerPhase::Running)
    );

    let completed = executor.complete_next().await.unwrap().unwrap();
    let evidence = report(&completed);
    assert_eq!(completed.source_instance_id, node(3));
    assert_eq!(completed.target_instance_id, node(2));
    assert_eq!(evidence.operation_id, operation(1));
    assert_eq!(evidence.attempt_id, attempt(1));
    assert_eq!(evidence.effect, Effect::None);
    assert_eq!(
        evidence.result,
        ExecutionResult::Succeeded {
            output: json!({"message": "你好", "items": [1, null, true]}),
        }
    );
    assert_eq!(
        executor.worker().phase(attempt(1)),
        Some(WorkerPhase::Completed)
    );
    assert_eq!(executor.report(attempt(1)), Some(completed.clone()));

    assert_eq!(
        authority.receive_report(completed.clone()).unwrap(),
        ReportDisposition::Adopted
    );
    let view = authority.operation(operation(1)).unwrap();
    assert_eq!(view.phase, OperationPhase::Reported);
    assert_eq!(view.adopted_report, Some(evidence.report_id));
    assert_eq!(authority.report(evidence.report_id), Some(&completed));
}

#[tokio::test(start_paused = true)]
async fn delay_returns_after_the_requested_virtual_time() {
    let limits = Limits::default();
    let mut authority = Authority::new(node(2), vec![node(3)], limits).unwrap();
    let mut executor = WorkerExecutor::new(node(3), node(2), limits).unwrap();
    let dispatch = authority
        .submit(
            request(
                1,
                TestTask::Delay {
                    delay_ms: 250,
                    value: json!("later"),
                },
            ),
            attempt(1),
        )
        .unwrap()
        .dispatch;
    executor.accept(dispatch).unwrap();
    assert_eq!(executor.start_ready(), 1);

    let started = tokio::time::Instant::now();
    let completed = executor.complete_next().await.unwrap().unwrap();
    assert_eq!(started.elapsed(), std::time::Duration::from_millis(250));
    assert_eq!(report(&completed).effect, Effect::None);
    assert_eq!(
        report(&completed).result,
        ExecutionResult::Succeeded {
            output: json!("later")
        }
    );
}

#[tokio::test]
async fn task_failure_returns_evidence_and_releases_its_slot() {
    let mut limits = Limits::default();
    limits.max_concurrency = 1;
    let mut authority = Authority::new(node(2), vec![node(3)], limits).unwrap();
    let mut executor = WorkerExecutor::new(node(3), node(2), limits).unwrap();
    for (id, task) in [
        (
            1,
            TestTask::Fail {
                message: "预期失败".into(),
            },
        ),
        (2, TestTask::Echo(json!("still runs"))),
    ] {
        let dispatch = authority
            .submit(request(id, task), attempt(id))
            .unwrap()
            .dispatch;
        executor.accept(dispatch).unwrap();
    }

    assert_eq!(executor.start_ready(), 1);
    let failed = executor.complete_next().await.unwrap().unwrap();
    assert_eq!(report(&failed).attempt_id, attempt(1));
    assert_eq!(report(&failed).effect, Effect::None);
    assert_eq!(
        report(&failed).result,
        ExecutionResult::Failed {
            error: "预期失败".into()
        }
    );
    assert_eq!(executor.in_flight(), 0);
    authority.receive_report(failed).unwrap();

    assert_eq!(executor.start_ready(), 1);
    let succeeded = executor.complete_next().await.unwrap().unwrap();
    assert_eq!(report(&succeeded).attempt_id, attempt(2));
    assert_eq!(
        report(&succeeded).result,
        ExecutionResult::Succeeded {
            output: json!("still runs")
        }
    );
    authority.receive_report(succeeded).unwrap();
    assert_eq!(executor.start_ready(), 0);
    assert!(executor.complete_next().await.unwrap().is_none());
}

#[tokio::test(start_paused = true)]
async fn concurrency_is_bounded_and_short_tasks_do_not_wait_for_long_ones() {
    let mut limits = Limits::default();
    limits.max_concurrency = 2;
    let mut executor = WorkerExecutor::new(node(3), node(2), limits).unwrap();
    for (id, task) in [
        (
            1,
            TestTask::Delay {
                delay_ms: 200,
                value: json!("long"),
            },
        ),
        (
            2,
            TestTask::Delay {
                delay_ms: 100,
                value: json!("short"),
            },
        ),
        (3, TestTask::Echo(json!("queued"))),
    ] {
        executor.accept(authorized(id, task)).unwrap();
    }
    assert_eq!(executor.start_ready(), 2);
    assert_eq!(executor.start_ready(), 0);
    assert_eq!(executor.in_flight(), 2);
    assert_eq!(
        executor.worker().phase(attempt(3)),
        Some(WorkerPhase::Queued)
    );

    let started = tokio::time::Instant::now();
    let short = executor.complete_next().await.unwrap().unwrap();
    assert_eq!(report(&short).attempt_id, attempt(2));
    assert_eq!(started.elapsed(), std::time::Duration::from_millis(100));
    assert_eq!(executor.start_ready(), 1);
    assert_eq!(executor.in_flight(), 2);

    let queued = executor.complete_next().await.unwrap().unwrap();
    assert_eq!(report(&queued).attempt_id, attempt(3));
    assert_eq!(started.elapsed(), std::time::Duration::from_millis(100));
    let long = executor.complete_next().await.unwrap().unwrap();
    assert_eq!(report(&long).attempt_id, attempt(1));
    assert_eq!(started.elapsed(), std::time::Duration::from_millis(200));
    assert_eq!(executor.in_flight(), 0);
    assert!(executor.complete_next().await.unwrap().is_none());
}

#[tokio::test(start_paused = true)]
async fn duplicate_dispatches_never_start_another_task_or_replace_the_report() {
    let mut executor = WorkerExecutor::new(node(3), node(2), Limits::default()).unwrap();
    let dispatch = authorized(
        1,
        TestTask::Delay {
            delay_ms: 100,
            value: json!("once"),
        },
    );
    assert_eq!(
        executor.accept(dispatch.clone()).unwrap(),
        WorkerPhase::Queued
    );
    assert_eq!(
        executor.accept(dispatch.clone()).unwrap(),
        WorkerPhase::Queued
    );
    assert_eq!(executor.start_ready(), 1);
    assert_eq!(
        executor.accept(dispatch.clone()).unwrap(),
        WorkerPhase::Running
    );
    assert_eq!(executor.start_ready(), 0);
    assert_eq!(executor.in_flight(), 1);

    let completed = executor.complete_next().await.unwrap().unwrap();
    for _ in 0..3 {
        assert_eq!(
            executor.accept(dispatch.clone()).unwrap(),
            WorkerPhase::Completed
        );
        assert_eq!(executor.report(attempt(1)), Some(completed.clone()));
        assert_eq!(executor.start_ready(), 0);
        assert!(executor.complete_next().await.unwrap().is_none());
    }
}

#[tokio::test(start_paused = true)]
async fn cancelling_a_wait_keeps_execution_alive_and_late_evidence_is_adopted() {
    let limits = Limits::default();
    let mut authority = Authority::new(node(2), vec![node(3)], limits).unwrap();
    let mut executor = WorkerExecutor::new(node(3), node(2), limits).unwrap();
    let original = request(
        1,
        TestTask::Delay {
            delay_ms: 100,
            value: json!("late"),
        },
    );
    let dispatch = authority
        .submit(original.clone(), attempt(1))
        .unwrap()
        .dispatch;
    executor.accept(dispatch.clone()).unwrap();
    authority.mark_dispatched(operation(1)).unwrap();
    assert_eq!(executor.start_ready(), 1);
    let started = tokio::time::Instant::now();

    let waiting = tokio::time::timeout(
        std::time::Duration::from_millis(10),
        executor.complete_next(),
    )
    .await;
    assert!(waiting.is_err());
    authority.mark_wait_timeout(operation(1)).unwrap();
    assert_eq!(executor.in_flight(), 1);
    assert_eq!(
        executor.worker().phase(attempt(1)),
        Some(WorkerPhase::Running)
    );
    assert_eq!(
        authority.operation(operation(1)).unwrap().phase,
        OperationPhase::Dispatched
    );

    let fast = authority
        .submit(request(2, TestTask::Echo(json!("fast"))), attempt(2))
        .unwrap()
        .dispatch;
    executor.accept(fast).unwrap();
    assert_eq!(executor.start_ready(), 1);
    let completed = executor.complete_next().await.unwrap().unwrap();
    assert_eq!(report(&completed).operation_id, operation(2));
    assert_eq!(started.elapsed(), std::time::Duration::from_millis(10));
    authority.receive_report(completed).unwrap();

    let late = executor.complete_next().await.unwrap().unwrap();
    assert_eq!(report(&late).attempt_id, attempt(1));
    assert_eq!(started.elapsed(), std::time::Duration::from_millis(100));
    assert_eq!(
        authority.receive_report(late.clone()).unwrap(),
        ReportDisposition::Adopted
    );
    assert_eq!(
        authority.receive_report(late).unwrap(),
        ReportDisposition::Duplicate
    );
    let view = authority.operation(operation(1)).unwrap();
    assert_eq!(view.phase, OperationPhase::Reported);
    assert_eq!(view.wait_status, WaitStatus::TimedOut);
    assert_eq!(
        authority.submit(original, attempt(99)).unwrap().dispatch,
        dispatch
    );
    assert_eq!(executor.start_ready(), 0);
}

#[tokio::test]
async fn oversized_expected_report_is_refused_before_work_admission() {
    let dispatch = authorized(1, TestTask::Echo(json!("x".repeat(1024))));
    let mut limits = Limits::default();
    limits.max_message_bytes = dispatch.to_json(&limits).unwrap().len();
    let mut executor = WorkerExecutor::new(node(3), node(2), limits).unwrap();
    assert!(matches!(
        executor.accept(dispatch),
        Err(StateError::Protocol(ProtocolError::MessageTooLarge))
    ));
    assert_eq!(executor.worker().phase(attempt(1)), None);
    assert_eq!(executor.start_ready(), 0);
    assert_eq!(executor.in_flight(), 0);

    executor
        .accept(authorized(2, TestTask::Echo(json!("fits"))))
        .unwrap();
    assert_eq!(executor.start_ready(), 1);
    let completed = executor.complete_next().await.unwrap().unwrap();
    completed.validate(&limits).unwrap();
    assert_eq!(report(&completed).attempt_id, attempt(2));
}

#[tokio::test]
async fn invalid_deliveries_never_start_execution() {
    let limits = Limits::default();
    let valid = authorized(1, TestTask::Echo(json!(null)));
    let mut invalid = Vec::new();
    let mut wrong = valid.clone();
    wrong.target_instance_id = node(99);
    invalid.push(wrong);
    let mut wrong = valid.clone();
    wrong.source_instance_id = node(99);
    invalid.push(wrong);
    let mut wrong = valid;
    wrong.protocol_version = 1;
    invalid.push(wrong);
    invalid.push(request(2, TestTask::Echo(json!(null))));
    let mut delay = authorized(
        1,
        TestTask::Delay {
            delay_ms: 0,
            value: json!(null),
        },
    );
    if let Message::DispatchAttempt(attempt) = &mut delay.message {
        attempt.operation.task = TestTask::Delay {
            delay_ms: limits.max_delay_ms + 1,
            value: json!(null),
        };
    }
    invalid.push(delay);

    let mut executor = WorkerExecutor::new(node(3), node(2), limits).unwrap();
    for delivery in invalid {
        assert!(executor.accept(delivery).is_err());
        assert_eq!(executor.worker().phase(attempt(1)), None);
        assert_eq!(executor.start_ready(), 0);
        assert_eq!(executor.in_flight(), 0);
        assert!(executor.complete_next().await.unwrap().is_none());
    }
}

#[tokio::test]
async fn queue_and_retention_limits_apply_before_spawning() {
    let mut limits = Limits::default();
    limits.queue_capacity = 1;
    limits.max_concurrency = 1;
    limits.max_records = 2;
    let mut executor = WorkerExecutor::new(node(3), node(2), limits).unwrap();
    let first = authorized(1, TestTask::Echo(json!("first")));
    let second = authorized(2, TestTask::Echo(json!("second")));
    executor.accept(first.clone()).unwrap();
    assert!(matches!(
        executor.accept(second.clone()),
        Err(StateError::QueueFull)
    ));
    assert_eq!(executor.worker().phase(attempt(2)), None);
    assert_eq!(executor.accept(first.clone()).unwrap(), WorkerPhase::Queued);

    assert_eq!(executor.start_ready(), 1);
    executor.accept(second).unwrap();
    assert_eq!(executor.start_ready(), 0);
    assert_eq!(executor.in_flight(), 1);
    let original = executor.complete_next().await.unwrap().unwrap();
    assert_eq!(executor.start_ready(), 1);
    let next = executor.complete_next().await.unwrap().unwrap();
    assert_eq!(report(&next).attempt_id, attempt(2));

    assert!(matches!(
        executor.accept(authorized(3, TestTask::Echo(json!("full")))),
        Err(StateError::Capacity)
    ));
    assert_eq!(executor.accept(first).unwrap(), WorkerPhase::Completed);
    assert_eq!(executor.report(attempt(1)), Some(original.clone()));
    assert_eq!(executor.start_ready(), 0);
}

#[tokio::test(start_paused = true)]
async fn zero_delay_needs_no_clock_advance() {
    let mut limits = Limits::default();
    limits.max_delay_ms = 0;
    let mut executor = WorkerExecutor::new(node(3), node(2), limits).unwrap();
    executor
        .accept(authorized(
            1,
            TestTask::Delay {
                delay_ms: 0,
                value: json!(null),
            },
        ))
        .unwrap();
    let started = tokio::time::Instant::now();
    assert_eq!(executor.start_ready(), 1);
    let completed = executor.complete_next().await.unwrap().unwrap();
    assert_eq!(started.elapsed(), std::time::Duration::ZERO);
    assert_eq!(
        report(&completed).result,
        ExecutionResult::Succeeded {
            output: json!(null)
        }
    );
}

#[tokio::test(start_paused = true)]
async fn one_hundred_operations_execute_on_two_workers_without_cross_talk() {
    let mut limits = Limits::default();
    limits.max_concurrency = 3;
    limits.queue_capacity = 50;
    limits.max_records = 128;
    let mut authority = Authority::new(node(2), vec![node(3), node(4)], limits).unwrap();
    let mut workers = [
        WorkerExecutor::new(node(3), node(2), limits).unwrap(),
        WorkerExecutor::new(node(4), node(2), limits).unwrap(),
    ];
    let mut identities = HashMap::new();
    for id in 1..=100 {
        let task = match id % 3 {
            0 => TestTask::Echo(json!({"operation": id})),
            1 => TestTask::Delay {
                delay_ms: 10,
                value: json!({"operation": id}),
            },
            _ => TestTask::Fail {
                message: format!("fail {id}"),
            },
        };
        let dispatch = authority
            .submit(request(id, task), attempt(id))
            .unwrap()
            .dispatch;
        let target = if dispatch.target_instance_id == node(3) {
            0
        } else {
            1
        };
        workers[target].accept(dispatch).unwrap();
        authority.mark_dispatched(operation(id)).unwrap();
        identities.insert(operation(id), id);
    }

    let mut received = HashSet::new();
    let mut reports = HashSet::new();
    let mut counts = [0; 2];
    let mut failures = 0;
    while received.len() < 100 {
        for worker in &mut workers {
            worker.start_ready();
            assert!(worker.in_flight() <= limits.max_concurrency);
        }
        let [left, right] = &mut workers;
        let (index, completed) = tokio::select! {
            result = left.complete_next(), if left.in_flight() > 0 => (0, result.unwrap().unwrap()),
            result = right.complete_next(), if right.in_flight() > 0 => (1, result.unwrap().unwrap()),
            else => panic!("execution stopped after {} reports", received.len()),
        };
        let evidence = report(&completed);
        let id = identities[&evidence.operation_id];
        assert!(
            received.insert(evidence.operation_id),
            "duplicate operation {id}"
        );
        assert!(
            reports.insert(evidence.report_id),
            "duplicate report for operation {id}"
        );
        assert_eq!(evidence.attempt_id, attempt(id));
        assert_eq!(evidence.effect, Effect::None);
        match (id % 3, &evidence.result) {
            (0 | 1, ExecutionResult::Succeeded { output }) => {
                assert_eq!(*output, json!({"operation": id}));
            }
            (2, ExecutionResult::Failed { error }) => {
                assert_eq!(*error, format!("fail {id}"));
                failures += 1;
            }
            (_, other) => panic!("unexpected result for operation {id}: {other:?}"),
        }
        assert_eq!(workers[index].report(attempt(id)), Some(completed.clone()));
        assert_eq!(
            authority.receive_report(completed).unwrap(),
            ReportDisposition::Adopted
        );
        counts[index] += 1;
    }
    assert_eq!(counts, [50, 50]);
    assert_eq!(failures, 33);
    for id in 1..=100 {
        let view = authority.operation(operation(id)).unwrap();
        assert_eq!(view.phase, OperationPhase::Reported);
        let retained = authority.report(view.adopted_report.unwrap()).unwrap();
        assert_eq!(report(retained).operation_id, operation(id));
    }
    for worker in &mut workers {
        assert_eq!(worker.start_ready(), 0);
        assert_eq!(worker.in_flight(), 0);
        assert!(worker.complete_next().await.unwrap().is_none());
    }
}
