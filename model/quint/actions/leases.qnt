// Frame-complete lease and authorization transitions.
module coreActionsLeases {
  import coreLogicLeases.* from "../logic/leases"
  export coreLogicLeases.*

  action createExecution(e: int): bool = all {
    authority.online,
    canCreate(authority.durable, e),
    authority' = { ...authority, durable: applyCreate(authority.durable, e) },
    workers' = workers, network' = network, external' = external, clock' = clock,
  }

  // 将数据库领取与 Worker 得知 token 合并为一步,是此模型的抽象收窄;不验证领取响应丢失协议.
  action claimExecution(e: int, w: int): bool = {
    val local = workers.get(w)
    val nextLedger = applyClaim(authority.durable, e, w, local.incarnation, clock)
    val token = tokenFor(nextLedger, e)
    all {
      authority.online, local.alive, canClaim(authority.durable, e, clock),
      authority' = { ...authority, durable: nextLedger },
      workers' = workers.set(w, { ...local, leases: local.leases.union(Set(token)) }),
      network' = network, external' = external, clock' = clock,
    }
  }

  // 同一步先持久化许可再形成回复;消息可丢,但重发只能返回同一份已保存 grant.
  action authorizeStart(t: Token): bool = all {
    authority.online, network.contains(StartRequest(t)),
    canAuthorize(authority.durable, t, clock),
    authority' = { ...authority, durable: applyAuthorize(authority.durable, t, clock) },
    network' = network.exclude(Set(StartRequest(t))).union(Set(StartReply(t))),
    workers' = workers, external' = external, clock' = clock,
  }

  action expireLease(e: int): bool = all {
    authority.online, canExpire(authority.durable, e, clock),
    authority' = { ...authority, durable: applyExpire(authority.durable, e) },
    workers' = workers, network' = network, external' = external, clock' = clock,
  }

  action renewLease(t: Token): bool = all {
    authority.online, canRenew(authority.durable, t, clock),
    authority' = { ...authority, durable: applyRenew(authority.durable, t, clock) },
    workers' = workers, network' = network,
    external' = { ...external, marks: external.marks.union(Set("renewed")) },
    clock' = clock,
  }
}
