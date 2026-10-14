// Checkpoint instrumentation only; all protocol changes use the existing actions.
module workerTrace {
  const VARIANT: int
  import beamletCore(WORKERS=Set(1,2),EXECUTIONS=Set(1,2),REPORT_IDS=Set(1,2,3,4),
    CLOCK_VALUES=0.to(6),MAX_INCARNATION=2,MAX_GENERATION=3,TTL=2,
    ALLOW_REPEAT=false,CAN_FENCE=false).* from "./model/beamletCore"
  pure val t:Token={exec:1,worker:1,incarnation:1,generation:1}
  pure def phaseName(a:Attempt):str=if(not(a.exists)) "absent" else match a.phase {
    | Prepared=>"prepared" | StartAuthorized=>"start_authorized" | Waiting=>"waiting" | Unknown=>"unknown" | Resolved=>"resolved" }
  pure def knowledgeName(a:Attempt):str=match a.knowledge {
    | NoKnowledge=>"none" | SuccessKnown=>"success" | FailureKnown=>"failure" | NotExecutedKnown=>"not_executed" }
  type Row={op:str,online:bool,phase:str,current:str,execution:str,knowledge:str,revision:int,
    reports:int,workerReports:int,queryReports:int,conflictsFree:bool,outcome:str,value:int,
    calls:int,finished:bool,workerAlive:bool,incarnation:int}
  var rows:List[Row]
  action keepRows=rows'=rows
  action mark(op:str):bool={
    val l=authority.durable
    all { safety,
      rows'=rows.append({op:op,online:authority.online,phase:if(l.phase==Open) "open" else "closed",
        current:if(l.current==NoCurrent) "none" else "1",execution:phaseName(l.attempts.get(1)),
        knowledge:knowledgeName(l.attempts.get(1)),revision:l.revision,reports:l.reports.size(),
        workerReports:l.reports.filter(r=>match r.origin {| ByWorker(_)=>true | _=>false}).size(),
        queryReports:l.reports.filter(r=>r.origin==ByQuery).size(),conflictsFree:noConflicts(l),
        outcome:if(l.outcomes.length()==0) "none" else if(l.outcomes.head().kind==OutcomeCancelled) "cancelled" else "succeeded",
        value:if(l.outcomes.length()==0) -1 else l.outcomes.head().value,
        calls:external.invocations.length(),finished:external.finished.get(1)!=ResourceUnfinished,
        workerAlive:workers.get(1).alive,incarnation:workers.get(1).incarnation}),
      authority'=authority,workers'=workers,network'=network,external'=external,clock'=clock }
  }
  action duplicateGrant=all {requestStart(t),keepRows}.then(all {resendGrant(t),keepRows})
    .then(all {discardDuplicateGrant(t),keepRows}).then(mark("duplicate_grant"))
  action finishLive=all {completeAtResource(1,Success),keepRows}
    .then(all {publishCompletion(t),keepRows}).then(mark("complete_retained"))
    .then(all {restartCoordinator,keepRows}).then(mark("authority_up"))
    .then(all {receiveReport(completionReport(external,t)),keepRows})
    .then(all {receiveReceipt(completionReport(external,t)),keepRows}).then(mark("flush"))
  action finishLost=all {crashWorker(1),keepRows}.then(mark("worker_down"))
    .then(all {completeAtResource(1,Success),keepRows}).then(mark("complete_lost"))
    .then(all {restartCoordinator,keepRows}).then(mark("authority_up"))
    .then(all {restartWorker(1),keepRows}).then(mark("worker_up"))
  action query=all {queryExternal(1,3),keepRows}
    .then(all {receiveReport(queryReport(external,1,3)),keepRows}).then(mark("query"))
  action duplicateReport=all {loseMessage(StoredReceipt(queryReport(external,1,3))),keepRows}
    .then(all {acknowledgeDuplicate(queryReport(external,1,3)),keepRows}).then(mark("duplicate_query"))
  action traceInit=all {init,rows'=List()}.then(mark("submit"))
    .then(all {createExecution(1),keepRows}).then(mark("create"))
    .then(all {claimExecution(1,1),keepRows}).then(mark("claim"))
    .then(all {requestStart(t),keepRows}).then(all {authorizeStart(t),keepRows}).then(mark("authorize"))
    .then(all {receiveGrant(t),keepRows}).then(all {callExternal(t),keepRows}).then(mark("invoke"))
    .then(duplicateGrant)
    .then(if(VARIANT>=2) all {cancelIntent,keepRows}.then(mark("cancel")) else mark("keep_open"))
    .then(all {crashCoordinator,keepRows}).then(mark("authority_down"))
    .then(if(VARIANT==1 or VARIANT==3) finishLost else finishLive)
    .then(query).then(duplicateReport)
  action traceStep=all {false,authority'=authority,workers'=workers,network'=network,external'=external,clock'=clock,keepRows}
}
