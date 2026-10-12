// One shared unbound core instance and legal shared prefixes; scenario groups reuse this state.
module repeatingFixtures {

  import beamletCore.* from "../../beamletCore"
  export beamletCore.*

  pure val t1: Token = { exec: 1, worker: 1, incarnation: 1, generation: 1 }

  pure val t2: Token = { exec: 2, worker: 2, incarnation: 1, generation: 1 }

  pure val success1: Report = { id: 2, exec: 1, kind: Success, value: 0, origin: ByWorker(t1) }

  pure val success2: Report = { id: 2, exec: 2, kind: Success, value: 0, origin: ByWorker(t2) }

  pure val failure2: Report = { ...success2, kind: Failure }

  // 具体入口接受重复风险:旧尝试到期且已被替代,但 Worker 仍持有 t1 并可继续调用.
  action replacementInit = init.expect(safety)
    .then(createExecution(1)).expect(safety)
    .then(claimExecution(1, 1)).expect(safety)
    .then(requestStart(t1)).expect(safety)
    .then(authorizeStart(t1)).expect(safety)
    .then(receiveGrant(t1)).expect(safety)
    .then(moveClockTo(2)).expect(safety)
    .then(expireLease(1)).expect(safety)
    .then(replaceExecution(1, 2)).expect(safety)
    .then(claimExecution(2, 2)).expect(safety)
    .then(requestStart(t2)).expect(safety)
    .then(authorizeStart(t2)).expect(safety)
    .then(receiveGrant(t2)).expect(safety)

  // 构造"旧成功 + 当前失败"合法窗口:两边结果都已知,普通 Failed 仍应被旧成功阻塞.
  action oldSuccessCurrentFailureInit = replacementInit
    .then(callExternal(t1)).expect(safety)
    .then(completeAtResource(1, Success)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)
    .then(receiveReport(success1)).expect(safety)
    .then(callExternal(t2)).expect(safety)
    .then(completeAtResource(2, Failure)).expect(safety)
    .then(publishCompletion(t2)).expect(safety)
    .then(receiveReport(failure2)).expect(safety)

  pure val reconciliationPolicy: ReconciliationPolicy = {
    operators: Set(1), registeredRules: Set(rule1v1, rule2v1), excludable: Set(success1), resolutions: Set(), withdrawals: Set(),
  }

  def manualExclusion: Decision = proposeDecision(authority.durable, success1, ExcludeFromJudgment, Operator(1))

  def manualAdoption: Decision = proposeDecision(authority.durable, success1, AdoptSuccess, Operator(1))

  action reconciliationStep = stepWithReconciliation(reconciliationPolicy)

  action commandStep = stepWithCommands(reconciliationPolicy)

  // Fixed proposals preserve what the caller reviewed before delayed delivery.
  // revision=7 来自上方真实前缀的判断变化;故意固定为 pure 值以测试延迟处理,不能随当前值刷新.
  pure val exclusionCommand: ReconciliationCommand = {
    id: 1, decision: {
      kind: ExcludeFromJudgment, report: success1, actor: Operator(1), basis: ContractExclusion,
      reviewedRevision: 7, evidence: Set(), supersedes: Set(),
    },
  }

  pure val adoptionCommand: ReconciliationCommand = {
    id: 2, decision: { ...exclusionCommand.decision, kind: AdoptSuccess, basis: VerifiedCompletion },
  }

  pure val queryReview: JudgmentView = {
    base: {
      phase: Open, current: Current(2), reports: Set(success1, failure2, querySuccess),
      attempts: Set(1, 2).mapBy(e => {
        exists: true, phase: Resolved, grant: StartGrant(if (e == 1) t1 else t2),
        knowledge: if (e == 1) SuccessKnown else FailureKnown, conflict: false,
      }),
    },
    decisions: List(),
  }

  pure val excludedRecord: CommandRecord = { command: exclusionCommand, outcomes: List(), decisionIndex: 0 }

  pure val adoptedRecord: CommandRecord = {
    command: adoptionCommand, outcomes: List({ kind: OutcomeSucceeded, value: 0, exec: Current(1) }), decisionIndex: 0,
  }

  pure val querySuccess: Report = { id: 3, exec: 1, kind: Success, value: 0, origin: ByQuery }

  action committedExclusionInit = oldSuccessCurrentFailureInit.expect(commandSafety)
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, exclusionCommand)).expect(commandSafety)

  // 两份请求先同时在途再顺序处理;同 ID 异内容优先报身份冲突,新 ID 才校验审查版本.
  action competingCommandsInit(first: ReconciliationCommand, second: ReconciliationCommand): bool =
    oldSuccessCurrentFailureInit
      .then(sendReconciliationCommand(first)).expect(commandSafety)
      .then(sendReconciliationCommand(second)).expect(commandSafety)
      .then(receiveReconciliationCommand(reconciliationPolicy, first)).expect(commandSafety)
      .then(receiveReconciliationCommand(reconciliationPolicy, second)).expect(commandSafety)

  pure val staleRejection: RejectedCommandRecord = {
    command: exclusionCommand, result: ReviewStale({
      revision: 8, current: Current(2), reports: Set(success1, failure2, querySuccess), view: queryReview,
    }),
  }

  pure val ineligibleRejection: RejectedCommandRecord = {
    command: exclusionCommand, result: DecisionIneligible,
  }

  pure val readonlyAccess: CommandAccess = { maySubmit: false, mayRead: true }

  pure val noAccess: CommandAccess = { maySubmit: false, mayRead: false }

  pure val querySuccess4: Report = { ...querySuccess, id: 4 }

  // 在发送与处理之间插入新证据,真实保存 stale 拒绝;该前缀已成立的见证不算后续新增覆盖.
  action rejectedStaleInit = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(queryExternal(1, 3)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, exclusionCommand)).expect(commandSafety)

  action rejectedIneligibleInit = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand({ ...reconciliationPolicy, excludable: Set() }, exclusionCommand))
      .expect(commandSafety)
}
