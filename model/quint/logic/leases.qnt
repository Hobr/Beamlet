// Reference-model adapters: shared execution rules plus judgment revision bookkeeping.
module coreLogicLeases {
  import coreLogicJudgment.* from "./judgment"
  export coreLogicJudgment.*
  import executionLeaseLogic as shared from "./execution_leases"

  pure def canCreate(l: Ledger, e: int): bool =
    shared::canCreate(l, e)

  pure def applyCreate(l: Ledger, e: int): Ledger =
    advanceJudgment(l, shared::applyCreate(l, e))

  pure def leaseKey(t: Token): LeaseKey =
    shared::leaseKey(t)

  pure def tokenFor(l: Ledger, e: int): Token =
    shared::tokenFor(l, e)

  pure def leaseValid(l: Ledger, t: Token, now: int): bool =
    shared::leaseValid(l, t, now)

  pure def canClaim(l: Ledger, e: int, now: int): bool =
    shared::canClaim(l, e, now)

  pure def applyClaim(l: Ledger, e: int, w: int, inc: int, now: int): Ledger =
    shared::applyClaim(l, e, w, inc, now)

  pure def canAuthorize(l: Ledger, t: Token, now: int): bool =
    shared::canAuthorize(l, t, now)

  pure def applyAuthorize(l: Ledger, t: Token, now: int): Ledger =
    advanceJudgment(l, shared::applyAuthorize(l, t, now))

  pure def canExpire(l: Ledger, e: int, now: int): bool =
    shared::canExpire(l, e, now)

  pure def applyExpire(l: Ledger, e: int): Ledger =
    advanceJudgment(l, shared::applyExpire(l, e))

  pure def stickyLease(l: Ledger, e: int): bool =
    shared::stickyLease(l, e)

  pure def canRenew(l: Ledger, t: Token, now: int): bool =
    shared::canRenew(l, t, now)

  pure def applyRenew(l: Ledger, t: Token, now: int): Ledger =
    shared::applyRenew(l, t, now)
}
