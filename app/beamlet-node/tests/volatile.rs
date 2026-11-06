use beamlet_node::{
    memory::{
        Admission, Authority, OperationPhase, ReportDisposition, StateError, WaitStatus, Worker,
        WorkerPhase,
    },
    protocol::{
        AttemptId, DispatchAttempt, Effect, Envelope, ExecutionResult, Limits, Message,
        OperationId, ProtocolError, ReportId, RoleInstanceId, SubmitOperation, SubmitReport,
        TestTask,
    },
};
use serde_json::{Value, json};

fn node(id: u128) -> RoleInstanceId {
    id.into()
}
fn operation(id: u128) -> OperationId {
    id.into()
}
fn attempt(id: u128) -> AttemptId {
    id.into()
}
fn report_id(id: u128) -> ReportId {
    id.into()
}

fn authority(limits: Limits) -> Authority {
    Authority::new(node(2), vec![node(3), node(4)], limits).expect("valid Authority fixture")
}

fn request(id: u128, input: Value) -> Envelope {
    Envelope::new(
        node(1),
        node(2),
        Message::SubmitOperation(SubmitOperation::new(operation(id), TestTask::Echo(input))),
    )
}

fn dispatch(authority: &mut Authority, id: u128) -> Envelope {
    authority
        .submit(request(id, json!(id.to_string())), attempt(id))
        .expect("fixture submission")
        .dispatch
}

fn authorization(envelope: &Envelope) -> &DispatchAttempt {
    match &envelope.message {
        Message::DispatchAttempt(attempt) => attempt,
        other => panic!("expected DispatchAttempt, got {other:?}"),
    }
}

fn evidence(dispatch: &Envelope, id: u128, effect: Effect, result: ExecutionResult) -> Envelope {
    Envelope::new(
        dispatch.target_instance_id,
        dispatch.source_instance_id,
        Message::SubmitReport(SubmitReport::for_attempt(
            report_id(id),
            authorization(dispatch),
            effect,
            result,
        )),
    )
}

fn success(dispatch: &Envelope, id: u128) -> Envelope {
    evidence(
        dispatch,
        id,
        Effect::None,
        ExecutionResult::Succeeded {
            output: json!("ok"),
        },
    )
}

#[test]
fn all_three_messages_and_fixed_tasks_round_trip() {
    let limits = Limits::default();
    let mut a = authority(limits);
    let d = dispatch(&mut a, 1);
    let mut messages = vec![request(1, json!({"b": 2, "a": [1, null, true]})), d.clone()];
    for task in [
        TestTask::Delay {
            delay_ms: 10,
            value: json!("later"),
        },
        TestTask::Fail {
            message: "test failure".into(),
        },
    ] {
        messages.push(Envelope::new(
            node(1),
            node(2),
            Message::SubmitOperation(SubmitOperation::new(operation(2), task)),
        ));
    }
    for result in [
        ExecutionResult::Succeeded {
            output: json!({"ok": true}),
        },
        ExecutionResult::Failed {
            error: "test failure".into(),
        },
        ExecutionResult::Rejected {
            error: "invalid input".into(),
        },
    ] {
        messages.push(evidence(&d, 1, Effect::None, result));
    }
    for envelope in messages {
        let encoded = envelope.to_json(&limits).expect("valid envelope");
        assert_eq!(
            Envelope::from_json(&encoded, &limits).expect("round trip"),
            envelope
        );
    }
    let wire = serde_json::to_value(success(&d, 1)).expect("report JSON");
    assert_eq!(wire["message"]["body"]["outcome"], "succeeded");
    assert!(wire["message"]["body"].get("result").is_none());
}

#[test]
fn decoder_rejects_unknown_fields_kinds_constraints_and_invalid_delay() {
    let limits = Limits::default();
    let base = serde_json::to_value(request(1, json!(null))).expect("request JSON");
    let mut cases = Vec::new();
    let mut value = base.clone();
    value["unexpected"] = json!(true);
    cases.push(value);
    let mut value = base.clone();
    value["protocol_version"] = json!(1);
    cases.push(value);
    let mut value = base.clone();
    value["message"]["kind"] = json!("register_capabilities");
    cases.push(value);
    let mut value = base.clone();
    value["message"]["body"]["unexpected"] = json!(1);
    cases.push(value);
    let mut value = base.clone();
    value["message"]["body"]["constraints"] = json!({"retry": true});
    cases.push(value);
    let mut value = base.clone();
    value["message"]["body"]["task"] = json!({"kind": "unknown", "input": null});
    cases.push(value);
    for delay in [
        json!(-1),
        json!(1.5),
        json!("10"),
        json!(limits.max_delay_ms + 1),
    ] {
        let mut value = base.clone();
        value["message"]["body"]["task"] =
            json!({"kind": "delay", "input": {"delay_ms": delay, "value": null}});
        cases.push(value);
    }
    for value in cases {
        assert!(
            Envelope::from_json(&serde_json::to_vec(&value).expect("case JSON"), &limits).is_err(),
            "invalid input accepted: {value}"
        );
    }
}

#[test]
fn report_decoder_rejects_extra_or_contradictory_outcome_fields() {
    let limits = Limits::default();
    let mut a = authority(limits);
    let d = dispatch(&mut a, 1);
    let base = serde_json::to_value(success(&d, 1)).expect("report JSON");
    for field in ["unexpected", "error"] {
        let mut value = base.clone();
        value["message"]["body"][field] = json!("not valid for success");
        assert!(
            Envelope::from_json(&serde_json::to_vec(&value).expect("case JSON"), &limits).is_err(),
            "extra report field accepted: {field}"
        );
    }
}

#[test]
fn byte_limit_is_inclusive_and_checked_before_parsing() {
    let envelope = request(1, json!("payload"));
    let encoded = envelope.to_json(&Limits::default()).expect("valid JSON");
    let mut limits = Limits::default();
    limits.max_message_bytes = encoded.len();
    assert_eq!(
        Envelope::from_json(&encoded, &limits).expect("exact limit"),
        envelope
    );
    limits.max_message_bytes -= 1;
    assert!(matches!(
        Envelope::from_json(&encoded, &limits),
        Err(ProtocolError::MessageTooLarge)
    ));
    assert!(matches!(
        envelope.to_json(&limits),
        Err(ProtocolError::MessageTooLarge)
    ));
    assert!(matches!(
        Envelope::from_json(&vec![b'?'; limits.max_message_bytes + 1], &limits),
        Err(ProtocolError::MessageTooLarge)
    ));
}

#[test]
fn failure_does_not_imply_no_effect_and_rejection_requires_no_effect() {
    let limits = Limits::default();
    let mut a = authority(limits);
    let d = dispatch(&mut a, 1);
    let unknown = evidence(
        &d,
        1,
        Effect::Unknown,
        ExecutionResult::Failed {
            error: "remote timeout".into(),
        },
    );
    assert_eq!(
        Envelope::from_json(&unknown.to_json(&limits).expect("valid evidence"), &limits)
            .expect("decoded evidence"),
        unknown
    );
    let rejected = evidence(
        &d,
        2,
        Effect::Unknown,
        ExecutionResult::Rejected {
            error: "refused before execution".into(),
        },
    );
    assert!(matches!(
        rejected.validate(&limits),
        Err(ProtocolError::InvalidRejectionEffect)
    ));
}

#[test]
fn duplicate_submission_reuses_attempt_and_does_not_advance_routing() {
    let mut a = authority(Limits::default());
    let first = a
        .submit(request(1, json!({"a": 1, "b": 2})), attempt(1))
        .expect("first submission");
    let duplicate = a
        .submit(request(1, json!({"b": 2, "a": 1})), attempt(99))
        .expect("duplicate submission");
    assert_eq!(first.admission, Admission::New);
    assert_eq!(duplicate.admission, Admission::Duplicate);
    assert_eq!(first.dispatch, duplicate.dispatch);
    assert!(matches!(
        a.submit(request(1, json!("changed")), attempt(100)),
        Err(StateError::OperationConflict)
    ));
    let second = a
        .submit(request(2, json!({"a": 1, "b": 2})), attempt(2))
        .expect("equal input, new identity");
    assert_eq!(first.dispatch.target_instance_id, node(3));
    assert_eq!(second.dispatch.target_instance_id, node(4));
    assert_eq!(authorization(&second.dispatch).attempt_id, attempt(2));
}

#[test]
fn attempt_id_cannot_be_reused_for_another_operation() {
    let mut a = authority(Limits::default());
    dispatch(&mut a, 1);
    assert!(matches!(
        a.submit(request(2, json!(null)), attempt(1)),
        Err(StateError::AttemptConflict)
    ));
    assert!(a.operation(operation(2)).is_none());
    assert_eq!(
        dispatch(&mut a, 2).target_instance_id,
        node(4),
        "refusal must not advance routing"
    );
}

#[test]
fn work_deduplicates_queued_running_and_completed_attempts() {
    let limits = Limits::default();
    let mut a = authority(limits);
    let d = dispatch(&mut a, 1);
    let mut w = Worker::new(node(3), node(2), limits).expect("valid Worker");
    assert_eq!(
        w.accept(d.clone()).expect("first delivery"),
        WorkerPhase::Queued
    );
    assert_eq!(
        w.accept(d.clone()).expect("queued duplicate"),
        WorkerPhase::Queued
    );
    assert_eq!(w.start_next(), Some(d.clone()));
    assert_eq!(
        w.accept(d.clone()).expect("running duplicate"),
        WorkerPhase::Running
    );
    assert!(
        w.start_next().is_none(),
        "duplicate must not add a second queue entry"
    );
    let report = success(&d, 1);
    w.complete(report.clone()).expect("completion");
    w.complete(report.clone()).expect("duplicate completion");
    assert_eq!(
        w.accept(d).expect("completed duplicate"),
        WorkerPhase::Completed
    );
    assert_eq!(w.report(attempt(1)), Some(&report));
    assert!(w.start_next().is_none());
}

#[test]
fn queue_and_running_limits_are_independent_and_invalid_completion_keeps_slot() {
    let mut limits = Limits::default();
    limits.queue_capacity = 1;
    limits.max_concurrency = 1;
    let mut a = Authority::new(node(2), vec![node(3)], limits).expect("valid Authority");
    let mut w = Worker::new(node(3), node(2), limits).expect("valid Worker");
    let d1 = dispatch(&mut a, 1);
    let d2 = dispatch(&mut a, 2);
    let d3 = dispatch(&mut a, 3);
    w.accept(d1.clone()).expect("first queued");
    assert!(matches!(w.accept(d2.clone()), Err(StateError::QueueFull)));
    assert_eq!(
        w.phase(attempt(2)),
        None,
        "refused delivery was not accepted"
    );
    assert_eq!(w.start_next(), Some(d1.clone()));
    w.accept(d2.clone()).expect("queue space available");
    assert!(w.start_next().is_none(), "running slot remains occupied");
    assert!(matches!(w.accept(d3.clone()), Err(StateError::QueueFull)));
    let mut bad = success(&d1, 1);
    bad.source_instance_id = node(99);
    assert!(matches!(w.complete(bad), Err(StateError::InvalidBinding)));
    assert!(
        w.start_next().is_none(),
        "invalid evidence must not release a slot"
    );
    w.complete(success(&d1, 1)).expect("first complete");
    assert_eq!(w.start_next(), Some(d2.clone()));
    w.accept(d3.clone()).expect("third queued");
    w.complete(success(&d2, 2)).expect("second complete");
    assert_eq!(w.start_next(), Some(d3));
}

#[test]
fn work_refuses_wrong_incarnation_untrusted_authority_and_conflicting_attempt() {
    let limits = Limits::default();
    let mut a = authority(limits);
    let d = dispatch(&mut a, 1);
    let mut w = Worker::new(node(3), node(2), limits).expect("valid Worker");
    let mut wrong = d.clone();
    wrong.target_instance_id = node(30);
    assert!(matches!(w.accept(wrong), Err(StateError::WrongTarget)));
    let mut wrong = d.clone();
    wrong.source_instance_id = node(20);
    assert!(matches!(
        w.accept(wrong),
        Err(StateError::UntrustedAuthority)
    ));
    assert_eq!(w.phase(attempt(1)), None);
    w.accept(d.clone()).expect("valid authorization");
    let mut wrong = d.clone();
    if let Message::DispatchAttempt(attempt) = &mut wrong.message {
        attempt.operation.task = TestTask::Echo(json!("changed"));
    }
    assert!(matches!(w.accept(wrong), Err(StateError::AttemptConflict)));
    assert_eq!(
        w.start_next(),
        Some(d),
        "original definition must be retained"
    );
}

#[test]
fn report_binding_is_checked_before_adoption() {
    let limits = Limits::default();
    let mut a = authority(limits);
    let d = dispatch(&mut a, 1);
    let valid = success(&d, 1);
    let mut wrong_source = valid.clone();
    wrong_source.source_instance_id = node(4);
    let mut wrong_target = valid.clone();
    wrong_target.target_instance_id = node(20);
    let mut wrong_attempt = valid.clone();
    if let Message::SubmitReport(report) = &mut wrong_attempt.message {
        report.attempt_id = attempt(99);
    }
    let mut wrong_operation = valid.clone();
    if let Message::SubmitReport(report) = &mut wrong_operation.message {
        report.operation_id = operation(99);
    }
    for invalid in [wrong_source, wrong_target, wrong_attempt, wrong_operation] {
        assert!(a.receive_report(invalid).is_err());
        assert!(a.report(report_id(1)).is_none());
        assert_eq!(
            a.operation(operation(1)).expect("retained request").phase,
            OperationPhase::Accepted
        );
    }
    assert_eq!(
        a.receive_report(valid).expect("valid evidence"),
        ReportDisposition::Adopted
    );
}

#[test]
fn reports_are_deduplicated_and_additional_evidence_does_not_replace_adoption() {
    let mut a = authority(Limits::default());
    let d = dispatch(&mut a, 1);
    let first = success(&d, 1);
    assert_eq!(
        a.receive_report(first.clone()).expect("first evidence"),
        ReportDisposition::Adopted
    );
    assert_eq!(
        a.receive_report(first.clone()).expect("duplicate evidence"),
        ReportDisposition::Duplicate
    );
    let conflicting = evidence(
        &d,
        1,
        Effect::Unknown,
        ExecutionResult::Failed {
            error: "different evidence".into(),
        },
    );
    assert!(matches!(
        a.receive_report(conflicting),
        Err(StateError::ReportConflict)
    ));
    assert_eq!(a.report(report_id(1)), Some(&first));
    let additional = evidence(
        &d,
        2,
        Effect::Unknown,
        ExecutionResult::Failed {
            error: "additional evidence".into(),
        },
    );
    assert_eq!(
        a.receive_report(additional.clone())
            .expect("additional evidence"),
        ReportDisposition::Additional
    );
    assert_eq!(a.report(report_id(2)), Some(&additional));
    assert_eq!(
        a.operation(operation(1)).expect("request").adopted_report,
        Some(report_id(1))
    );
    a.mark_dispatched(operation(1))
        .expect("late dispatch observation");
    assert_eq!(
        a.operation(operation(1)).expect("request").phase,
        OperationPhase::Reported,
        "late observations cannot erase evidence"
    );
}

#[test]
fn waiting_timeout_does_not_cancel_or_create_attempt_and_late_report_is_retained() {
    let mut a = authority(Limits::default());
    let d = dispatch(&mut a, 1);
    a.mark_dispatched(operation(1))
        .expect("dispatch observation");
    a.mark_wait_timeout(operation(1)).expect("wait timeout");
    let view = a.operation(operation(1)).expect("request remains");
    assert_eq!(view.dispatch, d);
    assert_eq!(view.phase, OperationPhase::Dispatched);
    assert_eq!(view.wait_status, WaitStatus::TimedOut);
    assert_eq!(view.adopted_report, None);
    a.receive_report(success(&d, 1)).expect("late report");
    let view = a.operation(operation(1)).expect("reported request");
    assert_eq!(view.phase, OperationPhase::Reported);
    assert_eq!(view.wait_status, WaitStatus::TimedOut);
    assert_eq!(
        a.submit(request(1, json!("1")), attempt(99))
            .expect("duplicate after timeout")
            .dispatch,
        d
    );
}

#[test]
fn identity_capacity_does_not_evict_records_or_prevent_duplicate_lookup() {
    let mut limits = Limits::default();
    limits.max_records = 1;
    let mut a = authority(limits);
    let d = dispatch(&mut a, 1);
    assert!(matches!(
        a.submit(request(2, json!(null)), attempt(2)),
        Err(StateError::Capacity)
    ));
    assert_eq!(
        a.submit(request(1, json!("1")), attempt(99))
            .expect("duplicate at capacity")
            .dispatch,
        d
    );
    let first = success(&d, 1);
    a.receive_report(first.clone()).expect("first report");
    assert_eq!(
        a.receive_report(first.clone())
            .expect("duplicate at capacity"),
        ReportDisposition::Duplicate
    );
    assert!(matches!(
        a.receive_report(success(&d, 2)),
        Err(StateError::Capacity)
    ));
    assert_eq!(
        a.operation(operation(1)).expect("request").adopted_report,
        Some(report_id(1))
    );
    let mut w = Worker::new(node(3), node(2), limits).expect("valid Worker");
    w.accept(d.clone()).expect("first attempt");
    w.start_next().expect("start first");
    w.complete(first).expect("complete first");
    assert_eq!(
        w.accept(d).expect("duplicate at capacity"),
        WorkerPhase::Completed
    );
    let mut other_authority =
        Authority::new(node(2), vec![node(3)], Limits::default()).expect("fixture Authority");
    assert!(matches!(
        w.accept(dispatch(&mut other_authority, 2)),
        Err(StateError::Capacity)
    ));
    assert!(
        w.report(attempt(1)).is_some(),
        "deduplication evidence was not evicted"
    );
}

#[test]
fn queued_attempt_can_be_rejected_but_cannot_claim_execution_before_start() {
    let limits = Limits::default();
    let mut a = authority(limits);
    let d = dispatch(&mut a, 1);
    let mut w = Worker::new(node(3), node(2), limits).expect("valid Worker");
    w.accept(d.clone()).expect("queued attempt");
    assert!(matches!(
        w.complete(success(&d, 1)),
        Err(StateError::InvalidTransition)
    ));
    assert_eq!(w.phase(attempt(1)), Some(WorkerPhase::Queued));
    let rejected = evidence(
        &d,
        2,
        Effect::None,
        ExecutionResult::Rejected {
            error: "rejected before start".into(),
        },
    );
    w.complete(rejected.clone()).expect("explicit rejection");
    assert!(w.start_next().is_none());
    assert_eq!(w.report(attempt(1)), Some(&rejected));
}

#[test]
fn completed_attempt_cannot_be_completed_again_with_different_evidence() {
    let limits = Limits::default();
    let mut a = authority(limits);
    let d = dispatch(&mut a, 1);
    let mut w = Worker::new(node(3), node(2), limits).expect("valid Worker");
    w.accept(d.clone()).expect("queued");
    w.start_next().expect("running");
    let first = success(&d, 1);
    w.complete(first.clone()).expect("first completion");
    assert!(w.complete(success(&d, 2)).is_err());
    assert_eq!(w.report(attempt(1)), Some(&first));
}

#[test]
fn restarted_incarnations_never_adopt_or_resume_old_messages() {
    let limits = Limits::default();
    let mut old_authority = authority(limits);
    let d = dispatch(&mut old_authority, 1);
    let mut restarted_work = Worker::new(node(30), node(2), limits).expect("restarted Worker");
    assert!(matches!(
        restarted_work.accept(d.clone()),
        Err(StateError::WrongTarget)
    ));
    assert!(restarted_work.start_next().is_none());
    let mut restarted_authority =
        Authority::new(node(20), vec![node(30)], limits).expect("restarted Authority");
    assert!(restarted_authority.operation(operation(1)).is_none());
    assert!(matches!(
        restarted_authority.receive_report(success(&d, 1)),
        Err(StateError::WrongTarget)
    ));
    assert_eq!(
        old_authority
            .operation(operation(1))
            .expect("original request")
            .dispatch,
        d
    );
}

#[test]
fn oversized_dispatch_is_refused_before_acceptance_or_routing_changes() {
    let incoming = request(1, json!("x".repeat(256)));
    let mut limits = Limits::default();
    limits.max_message_bytes = incoming.to_json(&limits).expect("incoming frame").len();
    let mut a = authority(limits);
    assert!(matches!(
        a.submit(incoming, attempt(1)),
        Err(StateError::Protocol(ProtocolError::MessageTooLarge))
    ));
    assert!(
        a.operation(operation(1)).is_none(),
        "an unencodable authorization must not be retained"
    );
    assert_eq!(
        a.submit(request(2, json!(null)), attempt(2))
            .expect("smaller dispatch fits")
            .dispatch
            .target_instance_id,
        node(3)
    );
}

#[test]
fn invalid_envelope_is_rejected_without_creating_state() {
    let mut a = authority(Limits::default());
    let mut invalid = request(1, json!(null));
    invalid.protocol_version = 99;
    assert!(matches!(
        a.submit(invalid, attempt(1)),
        Err(StateError::Protocol(ProtocolError::UnsupportedVersion(99)))
    ));
    assert!(a.operation(operation(1)).is_none());
    assert!(matches!(
        a.mark_wait_timeout(operation(1)),
        Err(StateError::UnknownOperation)
    ));
}

#[test]
fn invalid_limits_and_worker_lists_are_rejected() {
    let limits = Limits::default();
    assert!(matches!(
        Authority::new(node(2), vec![], limits),
        Err(StateError::InvalidWorkers)
    ));
    assert!(matches!(
        Authority::new(node(2), vec![node(3), node(3)], limits),
        Err(StateError::InvalidWorkers)
    ));
    for field in 0..4 {
        let mut invalid = limits;
        match field {
            0 => invalid.max_records = 0,
            1 => invalid.queue_capacity = 0,
            2 => invalid.max_concurrency = 0,
            _ => invalid.max_message_bytes = 0,
        }
        assert!(Worker::new(node(3), node(2), invalid).is_err());
    }
}

#[test]
fn one_hundred_operations_route_and_report_without_cross_talk() {
    let limits = Limits::default();
    let mut a = authority(limits);
    let mut workers = [
        Worker::new(node(3), node(2), limits).expect("Worker B"),
        Worker::new(node(4), node(2), limits).expect("Worker C"),
    ];
    let mut counts = [0, 0];
    for id in 100..200 {
        let d = dispatch(&mut a, id);
        a.mark_dispatched(operation(id))
            .expect("dispatch observation");
        let index = usize::from(d.target_instance_id == node(4));
        counts[index] += 1;
        workers[index]
            .accept(d)
            .expect("accept before any completions");
    }
    assert_eq!(counts, [50, 50]);
    let mut next_report = 1000;
    // 反转 Worker 与批次内的完成顺序, 验证乱序回报
    for w in workers.iter_mut().rev() {
        loop {
            let mut batch = Vec::new();
            while let Some(running) = w.start_next() {
                batch.push(running);
            }
            if batch.is_empty() {
                break;
            }
            assert!(batch.len() <= limits.max_concurrency);
            for running in batch.into_iter().rev() {
                let TestTask::Echo(input) = &authorization(&running).operation.task else {
                    panic!("expected echo fixture");
                };
                let r = evidence(
                    &running,
                    next_report,
                    Effect::None,
                    ExecutionResult::Succeeded {
                        output: input.clone(),
                    },
                );
                next_report += 1;
                w.complete(r.clone()).expect("retain completion");
                assert_eq!(
                    a.receive_report(r).expect("receive evidence"),
                    ReportDisposition::Adopted
                );
            }
        }
    }
    for id in 100..200 {
        let view = a.operation(operation(id)).expect("own request");
        assert_eq!(view.phase, OperationPhase::Reported);
        let r = a
            .report(view.adopted_report.expect("adopted report"))
            .expect("retained evidence");
        let Message::SubmitReport(report) = &r.message else {
            panic!("expected report");
        };
        assert_eq!(report.operation_id, operation(id));
        assert_eq!(
            report.result,
            ExecutionResult::Succeeded {
                output: json!(id.to_string())
            }
        );
    }
}
