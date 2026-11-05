use beamlet_agent::{
    Admission, Authority, Limits, OperationPhase, ReportDisposition, StateError, WaitStatus, Work,
    id::{AttemptId, NodeInstanceId, OperationId, ReportId},
    model::{Delivery, DispatchAttempt, Effect, ExecutionResult, Message, Operation, SubmitReport},
};
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};
use std::time::Duration;
use tokio::sync::mpsc;

#[derive(Clone, Debug, Eq, PartialEq)]
struct Input(&'static str);

type Envelope = Delivery<Input, &'static str, &'static str>;

async fn echo(attempt: DispatchAttempt<Input>) -> SubmitReport<&'static str, &'static str> {
    SubmitReport {
        report_id: (90 + attempt.attempt_id.as_u128()).into(),
        operation_id: attempt.operation.operation_id,
        attempt_id: attempt.attempt_id,
        effect: Effect::None,
        result: ExecutionResult::Succeeded {
            output: attempt.operation.task.0,
        },
    }
}

#[tokio::test]
async fn authority_and_work_complete_echo_only_through_messages() {
    let authority_id = NodeInstanceId::from(2);
    let work_id = NodeInstanceId::from(3);
    let operation_id = OperationId::from(1);
    let attempt_id = AttemptId::from(11);
    let mut authority = Authority::<Input, &'static str, &'static str>::new(
        authority_id,
        vec![work_id],
        Limits::default(),
    )
    .expect("authority configuration must be valid");
    let (dispatch_tx, mut dispatch_rx) = mpsc::channel::<Envelope>(1);
    let (report_tx, mut report_rx) = mpsc::channel::<Envelope>(1);

    let worker = tokio::spawn(async move {
        let mut work = Work::new(authority_id, vec![work_id], Limits::default())
            .expect("work configuration must be valid");
        let dispatch = dispatch_rx.recv().await.expect("dispatch must arrive");
        assert!(
            work.receive_dispatch(dispatch)
                .expect("authorization must be accepted")
                .is_none(),
            "a new authorization must not already have a cached report"
        );
        let report = work
            .next_report(echo)
            .await
            .expect("execution must complete without driver errors")
            .expect("echo must produce a report");
        report_tx.send(report).await.expect("report must be sent");
    });

    let accepted = authority
        .submit(
            Operation {
                operation_id,
                task: Input("hello"),
            },
            attempt_id,
        )
        .expect("operation must be accepted");
    assert_eq!(
        authority.operation(operation_id).unwrap().phase,
        OperationPhase::Accepted,
        "acceptance alone must not claim delivery or execution"
    );
    dispatch_tx
        .send(accepted.dispatch)
        .await
        .expect("dispatch must be sent");
    authority
        .mark_dispatched(operation_id)
        .expect("sending must be recorded separately from acceptance");
    let report = report_rx.recv().await.expect("report must arrive");
    worker.await.expect("work driver must finish");

    let before = authority.operation(operation_id).unwrap();
    assert_eq!(before.phase, OperationPhase::Dispatched);
    assert!(
        before.adopted_report.is_none(),
        "work completion must not mutate authority state through a shared object"
    );
    assert_eq!(report.source_instance_id, work_id);
    assert_eq!(report.target_instance_id, authority_id);
    assert!(matches!(
        &report.message,
        Message::SubmitReport(SubmitReport {
            operation_id: received_operation,
            attempt_id: received_attempt,
            effect: Effect::None,
            result: ExecutionResult::Succeeded { output: "hello" },
            ..
        }) if *received_operation == operation_id && *received_attempt == attempt_id
    ));
    assert_eq!(
        authority.receive_report(report.clone()).unwrap(),
        ReportDisposition::Adopted
    );
    let completed = authority.operation(operation_id).unwrap();
    assert_eq!(completed.phase, OperationPhase::Reported);
    assert_eq!(completed.adopted_report, Some(ReportId::from(101)));
    assert_eq!(authority.report(ReportId::from(101)), Some(&report));
}

#[tokio::test]
async fn duplicate_deliveries_reuse_one_execution_and_the_cached_report() {
    let mut authority = Authority::new(2.into(), vec![3.into()], Limits::default()).unwrap();
    let mut work = Work::new(2.into(), vec![3.into()], Limits::default()).unwrap();
    let operation = Operation {
        operation_id: 1.into(),
        task: Input("hello"),
    };
    let first = authority.submit(operation.clone(), 11.into()).unwrap();
    let duplicate = authority.submit(operation, 99.into()).unwrap();
    assert_eq!(duplicate.admission, Admission::Duplicate);
    assert_eq!(duplicate.dispatch, first.dispatch);
    assert_eq!(
        authority.operation(1.into()).unwrap().phase,
        OperationPhase::Accepted,
        "duplicate submission must not claim that a dispatch was sent"
    );

    assert!(
        work.receive_dispatch(first.dispatch.clone())
            .unwrap()
            .is_none()
    );
    assert!(
        work.receive_dispatch(duplicate.dispatch.clone())
            .unwrap()
            .is_none()
    );
    let executions = Arc::new(AtomicUsize::new(0));
    let execute = {
        let executions = Arc::clone(&executions);
        move |attempt| {
            executions.fetch_add(1, Ordering::SeqCst);
            echo(attempt)
        }
    };
    let report = work.next_report(&execute).await.unwrap().unwrap();
    assert_eq!(executions.load(Ordering::SeqCst), 1);
    assert_eq!(
        work.receive_dispatch(duplicate.dispatch).unwrap(),
        Some(report.clone()),
        "completed duplicates must return the original cached evidence"
    );
    assert!(work.next_report(&execute).await.unwrap().is_none());
    assert_eq!(executions.load(Ordering::SeqCst), 1);
    assert_eq!(
        authority.receive_report(report.clone()).unwrap(),
        ReportDisposition::Adopted
    );
    assert_eq!(
        authority.receive_report(report).unwrap(),
        ReportDisposition::Duplicate
    );
}

#[tokio::test(start_paused = true)]
async fn cancelled_work_wait_keeps_execution_and_late_evidence_separate_from_adoption() {
    let mut authority = Authority::new(2.into(), vec![3.into()], Limits::default()).unwrap();
    let mut work = Work::new(2.into(), vec![3.into()], Limits::default()).unwrap();
    let operation = Operation {
        operation_id: 1.into(),
        task: Input("late"),
    };
    let accepted = authority.submit(operation.clone(), 11.into()).unwrap();
    work.receive_dispatch(accepted.dispatch.clone()).unwrap();
    authority.mark_dispatched(1.into()).unwrap();
    let executions = Arc::new(AtomicUsize::new(0));
    let execute = {
        let executions = Arc::clone(&executions);
        move |attempt| {
            executions.fetch_add(1, Ordering::SeqCst);
            async move {
                tokio::time::sleep(Duration::from_millis(100)).await;
                echo(attempt).await
            }
        }
    };
    let started = tokio::time::Instant::now();
    assert!(
        tokio::time::timeout(Duration::from_millis(10), work.next_report(&execute))
            .await
            .is_err(),
        "the caller must be able to stop waiting without cancelling execution"
    );
    authority.mark_wait_timeout(1.into()).unwrap();
    let duplicate = authority.submit(operation, 99.into()).unwrap();
    assert_eq!(duplicate.admission, Admission::Duplicate);
    assert_eq!(duplicate.dispatch, accepted.dispatch);
    assert!(
        work.receive_dispatch(duplicate.dispatch.clone())
            .unwrap()
            .is_none()
    );

    let report = work.next_report(&execute).await.unwrap().unwrap();
    assert_eq!(started.elapsed(), Duration::from_millis(100));
    assert_eq!(executions.load(Ordering::SeqCst), 1);
    let waiting = authority.operation(1.into()).unwrap();
    assert_eq!(waiting.phase, OperationPhase::Dispatched);
    assert_eq!(waiting.wait_status, WaitStatus::TimedOut);
    assert!(waiting.adopted_report.is_none());
    assert_eq!(
        work.receive_dispatch(duplicate.dispatch).unwrap(),
        Some(report.clone()),
        "evidence must already be cached before authority adoption"
    );

    authority.receive_report(report).unwrap();
    let completed = authority.operation(1.into()).unwrap();
    assert_eq!(completed.phase, OperationPhase::Reported);
    assert_eq!(completed.wait_status, WaitStatus::TimedOut);
    assert_eq!(completed.adopted_report, Some(ReportId::from(101)));
    assert!(work.next_report(&execute).await.unwrap().is_none());
}

#[tokio::test]
async fn full_delivery_channel_retains_acceptance_without_retrying_or_reauthorizing() {
    let mut authority = Authority::new(2.into(), vec![3.into()], Limits::default()).unwrap();
    let mut work = Work::new(2.into(), vec![3.into()], Limits::default()).unwrap();
    let (dispatch_tx, mut dispatch_rx) = mpsc::channel::<Envelope>(1);
    let first = authority
        .submit(
            Operation {
                operation_id: 1.into(),
                task: Input("delivered"),
            },
            11.into(),
        )
        .unwrap();
    dispatch_tx.try_send(first.dispatch).unwrap();
    authority.mark_dispatched(1.into()).unwrap();
    let blocked_operation = Operation {
        operation_id: 2.into(),
        task: Input("pending"),
    };
    let blocked = authority
        .submit(blocked_operation.clone(), 12.into())
        .unwrap();
    let refused = dispatch_tx
        .try_send(blocked.dispatch.clone())
        .expect_err("the bounded delivery channel must refuse a second dispatch");
    let mpsc::error::TrySendError::Full(unsent) = refused else {
        panic!("expected channel backpressure rather than disconnection");
    };
    assert_eq!(unsent, blocked.dispatch);
    assert_eq!(
        authority.operation(2.into()).unwrap().phase,
        OperationPhase::Accepted,
        "failed delivery must not revoke acceptance or claim a sent dispatch"
    );
    assert!(
        work.next_report(echo).await.unwrap().is_none(),
        "authority acceptance must not enqueue work through a hidden local path"
    );

    let duplicate = authority.submit(blocked_operation, 99.into()).unwrap();
    assert_eq!(duplicate.admission, Admission::Duplicate);
    assert_eq!(duplicate.dispatch, blocked.dispatch);
    let delivered = dispatch_rx.recv().await.unwrap();
    work.receive_dispatch(delivered).unwrap();
    let report = work.next_report(echo).await.unwrap().unwrap();
    authority.receive_report(report).unwrap();

    assert!(matches!(
        dispatch_rx.try_recv(),
        Err(mpsc::error::TryRecvError::Empty)
    ));
    assert!(work.next_report(echo).await.unwrap().is_none());
    let pending = authority.operation(2.into()).unwrap();
    assert_eq!(pending.phase, OperationPhase::Accepted);
    assert!(pending.adopted_report.is_none());
    assert!(matches!(
        &pending.dispatch.message,
        Message::DispatchAttempt(attempt) if attempt.attempt_id == AttemptId::from(12)
    ));
}

#[tokio::test]
async fn invalid_messages_cannot_start_work_or_replace_retained_evidence() {
    let mut authority = Authority::new(2.into(), vec![3.into()], Limits::default()).unwrap();
    let mut work = Work::new(2.into(), vec![3.into()], Limits::default()).unwrap();
    let operation = Operation {
        operation_id: 1.into(),
        task: Input("bound"),
    };
    let accepted = authority.submit(operation.clone(), 11.into()).unwrap();
    let mut wrong_target = accepted.dispatch.clone();
    wrong_target.target_instance_id = 4.into();
    assert!(matches!(
        work.receive_dispatch(wrong_target),
        Err(StateError::WrongTarget)
    ));
    let mut wrong_authority = accepted.dispatch.clone();
    wrong_authority.source_instance_id = 9.into();
    assert!(matches!(
        work.receive_dispatch(wrong_authority),
        Err(StateError::UntrustedAuthority)
    ));
    assert!(matches!(
        work.receive_dispatch(Delivery::new(
            2.into(),
            3.into(),
            Message::SubmitOperation(operation),
        )),
        Err(StateError::WrongMessage)
    ));
    assert!(work.next_report(echo).await.unwrap().is_none());

    work.receive_dispatch(accepted.dispatch).unwrap();
    authority.mark_dispatched(1.into()).unwrap();
    let report = work.next_report(echo).await.unwrap().unwrap();
    let mut wrong_report_source = report.clone();
    wrong_report_source.source_instance_id = 4.into();
    assert!(matches!(
        authority.receive_report(wrong_report_source),
        Err(StateError::InvalidBinding)
    ));
    let mut wrong_report_target = report.clone();
    wrong_report_target.target_instance_id = 9.into();
    assert!(matches!(
        authority.receive_report(wrong_report_target),
        Err(StateError::WrongTarget)
    ));
    assert!(authority.report(ReportId::from(101)).is_none());
    assert!(
        authority
            .operation(1.into())
            .unwrap()
            .adopted_report
            .is_none()
    );

    authority.receive_report(report.clone()).unwrap();
    let mut conflicting = report.clone();
    let Message::SubmitReport(evidence) = &mut conflicting.message else {
        panic!("expected execution evidence");
    };
    evidence.result = ExecutionResult::Succeeded {
        output: "different",
    };
    assert!(matches!(
        authority.receive_report(conflicting),
        Err(StateError::ReportConflict)
    ));
    assert_eq!(authority.report(ReportId::from(101)), Some(&report));
}

#[tokio::test(start_paused = true)]
async fn two_independent_work_drivers_return_out_of_order_without_cross_talk() {
    let authority_id = NodeInstanceId::from(2);
    let mut authority =
        Authority::new(authority_id, vec![3.into(), 4.into()], Limits::default()).unwrap();
    let (report_tx, mut report_rx) = mpsc::channel::<Envelope>(1);
    let mut dispatch_senders = Vec::new();
    let mut workers = Vec::new();
    for instance in [NodeInstanceId::from(3), NodeInstanceId::from(4)] {
        let (dispatch_tx, mut dispatch_rx) = mpsc::channel::<Envelope>(1);
        dispatch_senders.push(dispatch_tx);
        let report_tx = report_tx.clone();
        workers.push(tokio::spawn(async move {
            let mut work = Work::new(authority_id, vec![instance], Limits::default()).unwrap();
            let dispatch = dispatch_rx.recv().await.unwrap();
            work.receive_dispatch(dispatch).unwrap();
            let report = work
                .next_report(move |attempt| async move {
                    if instance == NodeInstanceId::from(3) {
                        tokio::time::sleep(Duration::from_millis(10)).await;
                    }
                    echo(attempt).await
                })
                .await
                .unwrap()
                .unwrap();
            report_tx.send(report).await.unwrap();
        }));
    }
    drop(report_tx);
    for (sender, (operation, attempt, value, target)) in dispatch_senders
        .into_iter()
        .zip([(1, 11, "first", 3), (2, 12, "second", 4)])
    {
        let accepted = authority
            .submit(
                Operation {
                    operation_id: operation.into(),
                    task: Input(value),
                },
                attempt.into(),
            )
            .unwrap();
        assert_eq!(
            accepted.dispatch.target_instance_id,
            NodeInstanceId::from(target)
        );
        sender.send(accepted.dispatch).await.unwrap();
        authority.mark_dispatched(operation.into()).unwrap();
    }

    let mut observed = Vec::new();
    for _ in 0..2 {
        let report = report_rx.recv().await.unwrap();
        let Message::SubmitReport(evidence) = &report.message else {
            panic!("expected execution evidence");
        };
        let ExecutionResult::Succeeded { output } = evidence.result else {
            panic!("expected echo success");
        };
        observed.push((
            report.source_instance_id.as_u128(),
            evidence.operation_id.as_u128(),
            evidence.attempt_id.as_u128(),
            output,
        ));
        assert_eq!(
            authority.receive_report(report).unwrap(),
            ReportDisposition::Adopted
        );
    }
    assert_eq!(
        observed.iter().map(|item| item.0).collect::<Vec<_>>(),
        vec![4, 3],
        "the short task must report before the earlier slow task"
    );
    observed.sort_by_key(|item| item.0);
    assert_eq!(observed, vec![(3, 1, 11, "first"), (4, 2, 12, "second")]);
    for (operation, report) in [(1, 101), (2, 102)] {
        let view = authority.operation(operation.into()).unwrap();
        assert_eq!(view.phase, OperationPhase::Reported);
        assert_eq!(view.adopted_report, Some(ReportId::from(report)));
    }
    for worker in workers {
        worker.await.expect("independent work driver must finish");
    }
}
