// Durable observations across a bounded A/B -> C continuation, not a new protocol.
module callerTrace {
  const VARIANT:int
  import continuationProfiles(INTENTS=Set(1,2,3),AGENTS=Set(1,2),CALLS=Set(1,2),
    WORKERS=Set(1,2),EXECUTIONS=Set(1,2),REPORT_IDS=Set(1,2,3,4),
    CLOCK_VALUES=0.to(6),MAX_INCARNATION=2,MAX_GENERATION=3,TTL=2,
    ALLOW_REPEAT=false,CAN_FENCE=false).* from "./model/continuation/profiles"
  pure val resultA:CollectedResult={call:1,slot:1,intent:1,outcome:{kind:OutcomeSucceeded,exec:Current(1),value:1}}
  pure val nextRequest=nextDependencyFor(resultA).request
  type Item={exists:bool,phase:str,execution:str,knowledge:str,reports:int,callbacks:int,outcome:str,value:int,calls:int,finished:bool}
  type Row={op:str,catalog:int,sourceComplete:bool,nextExists:bool,nextComplete:bool,
    decision:bool,decisionSound:bool,manifestSound:bool,consumed:int,nextInput:int,a:Item,b:Item,c:Item}
  var rows:List[Row]
  action keepRows=rows'=rows
  pure def projectIntent(d:IntentData,x:ExternalState):Item={
    val l=d.ledger
    val a=l.attempts.get(1)
    {exists:d.exists,phase:if(l.phase==Open) "open" else "closed",
      execution:if(not(a.exists)) "absent" else match a.phase {
        | Prepared=>"prepared" | StartAuthorized=>"start_authorized" | Waiting=>"waiting" | Unknown=>"unknown" | Resolved=>"resolved" },
      knowledge:match a.knowledge { | NoKnowledge=>"none" | SuccessKnown=>"success" | FailureKnown=>"failure" | NotExecutedKnown=>"not_executed" },
      reports:l.reports.size(),callbacks:l.reports.filter(r=>match r.origin {| ByCallback(_)=>true | _=>false}).size(),
      outcome:if(l.outcomes.length()==0) "none" else if(l.outcomes.head().kind==OutcomeCancelled) "cancelled" else "succeeded",
      value:if(l.outcomes.length()==0) -1 else l.outcomes.head().value,
      calls:x.invocations.length(),finished:x.finished.get(1)!=ResourceUnfinished}
  }
  action mark(op:str):bool=all {
    continuationSafety,
    rows'=rows.append({op:op,catalog:multiStore.catalog.length(),sourceComplete:callerRounds.get(1).completed,
      nextExists:callerRounds.get(2).exists,nextComplete:callerRounds.get(2).completed,
      decision:progress.decision!=NoProgress,decisionSound:decisionSourcesSound,manifestSound:nextManifestSound,
      consumed:match progress.decision { | NoProgress=>-1 | ProgressCommitted(r)=>r.consumed.fold(-1,(_,v)=>v.outcome.value) },
      nextInput:if(callerRounds.get(2).exists) callerRounds.get(2).dependencies.fold(-1,(_,d)=>d.request.definition.input) else -1,
      a:projectIntent(multiStore.intents.get(1),resources.get(1)),b:projectIntent(multiStore.intents.get(2),resources.get(2)),
      c:projectIntent(multiStore.intents.get(3),resources.get(3))}),
    holdRuntime,callerRounds'=callerRounds,agentLocals'=agentLocals,holdProgress }
  action resolveBoth=all {resolveProgressReply({request:request,result:CreatedIntent(1)}),keepRows}
    .then(all {resolveProgressReply({request:requestB,result:CreatedIntent(2)}),keepRows})
  action start(i:int,w:int):bool={
    val t={...t1,worker:w}
    all {multiCreate(i,1),holdProgress,keepRows}
      .then(all {multiClaim(i,1,w),holdProgress,keepRows})
      .then(all {multiRequest(i,t),holdProgress,keepRows})
      .then(all {multiAuthorize(i,t,callbackHandler),holdProgress,keepRows})
      .then(all {multiGrant(i,scoped(i,StartReply(t)),t),holdProgress,keepRows})
      .then(all {multiCall(i,t),holdProgress,keepRows})
  }
  action finish(i:int,value:int):bool={
    val r=progressCallback(i,Success,value)
    all {multiComplete(i,1,Success,value),holdProgress,keepRows}
      .then(all {multiEmitCallback(i,r,true),holdProgress,keepRows})
      .then(all {multiReceive(i,scoped(i,ResultReport(r)),r),holdProgress,keepRows})
  }
  action restart=all {crashProgressAgent,keepRows}.then(mark("caller_down"))
    .then(all {restartProgressAgent,keepRows}).then(mark("caller_up"))
  action recoverRef(req:SubmissionRequest):bool=all {multiSend(1,req),holdProgress,keepRows}
    .then(all {multiSubmit(1,req),holdProgress,keepRows})
    .then(all {multiResolve(1,multiReply(multiStore,req)),holdProgress,keepRows})
  action recoverSources=recoverRef(request).then(recoverRef(requestB))
    .then(all {readProgressResult(sourceRefA),keepRows}).then(mark("recover_sources"))
  action lostSubmit=all {sendNext,keepRows}.then(all {submitNext,keepRows})
    .then(mark("lose_successor_reply"))
  action submitSuccessor=all {sendNext,keepRows}.then(all {submitNext,keepRows})
    .then(all {multiResolve(1,if(VARIANT==2) multiReply(multiStore,nextRequest) else {request:nextRequest,result:CreatedIntent(3)}),holdProgress,keepRows})
    .then(mark("submit_successor"))
  // Agent read caches are volatile in Quint. SQL may retain more; only committed
  // rounds/decisions and the authority/resource observations above are compared.
  action traceInit=all {multiInit,progress'=initialProgress,rows'=List()}
    .then(all {openRound(1,1,Set(dependencyA,dependencyB)),holdProgress,keepRows}).then(mark("open"))
    .then(all {multiSend(1,request),holdProgress,keepRows})
    .then(all {multiSend(1,requestB),holdProgress,keepRows})
    .then(all {multiSubmit(1,request),holdProgress,keepRows})
    .then(all {multiSubmit(1,requestB),holdProgress,keepRows})
    .then(resolveBoth).then(mark("submit_sources"))
    .then(start(1,1)).then(mark("start_a"))
    .then(start(2,1)).then(mark("start_b"))
    .then(finish(1,1)).then(mark("complete_a"))
    .then(all {readProgressResult(sourceRefA),keepRows}).then(mark("collect_a"))
    .then(all {decideA,keepRows}).then(mark("decide"))
    .then(if(VARIANT==0) restart else mark("before_manifest"))
    .then(all {registerNext,keepRows}).then(mark("register"))
    .then(if(VARIANT==2) lostSubmit else mark("before_send"))
    .then(if(VARIANT>0) restart else mark("after_restart"))
    .then(recoverSources).then(submitSuccessor)
    .then(start(3,2)).then(mark("start_c"))
    .then(finish(3,1)).then(mark("complete_c"))
    .then(all {readProgressResult(successorRef),keepRows})
    .then(all {collectProgressRound(2),keepRows}).then(mark("collect_c"))
    .then(finish(2,2)).then(mark("complete_b"))
    .then(all {readProgressResult(sourceRefB),keepRows})
    .then(all {collectProgressRound(1),keepRows}).then(mark("collect_sources"))
  action traceStep=all {false,holdRuntime,callerRounds'=callerRounds,agentLocals'=agentLocals,holdProgress,keepRows}
}
