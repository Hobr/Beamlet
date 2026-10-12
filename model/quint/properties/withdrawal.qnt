// Independent scoped-withdrawal checking, without using witness snapshots as execution gates.
module corePropertiesWithdrawal {
  import coreLogicCommands.* from "../logic/commands"
  export coreLogicCommands.*

  // 按每个接受前缀重建真实绑定,对照精确核验依据与范围,避免仅依赖准入布尔摘要.
  // 作用必须等于"原绑定减请求范围";历史链不回滚,未提及报告不受影响.
  val withdrawalScopeSound = {
    val checked = authority.durable.decisions.foldl({ valid: true, prefix: List() }, (s, w) => {
      val d = w.decision
      val before = historicalBindings(s.prefix)
      val afterPrefix = s.prefix.append(w)
      val scope = decisionAffectedReports(d)
      val validWithdrawal = d.kind != WithdrawDisposition or (
        d.evidence == Set() and d.basis == VerifiedWithdrawal and d.supersedes.size() > 0
          and scope.contains(d.report) and w.bindingsBefore == before
          and w.withdrawalsAtDecision.contains(d.supersedes)
          and d.supersedes.forall(ref => ref.reports.size() > 0 and ref.reports.forall(r =>
            before.exists(b => b.decisionIndex == ref.decisionIndex and b.item.report == r
              and s.prefix.nth(b.decisionIndex).acceptedBase == w.acceptedBase)))
          // Remove only the requested reports, with no replacement or resurrection.
          and historicalBindings(afterPrefix) == before.filter(b => not(scope.contains(b.item.report))))
      { valid: s.valid and validWithdrawal, prefix: afterPrefix }
    })
    checked.valid
  }

  // 撤销命令的原结果永远无 Outcome;之后新决定可以独立终结,不改变撤销的原结果.
  val withdrawalCommandsNonterminal = authority.durable.commands.foldl(true, (ok, r) =>
    ok and (r.command.decision.kind == WithdrawDisposition implies r.outcomes == List()))

  val withdrawalReached = authority.durable.decisions.select(w =>
    w.decision.kind == WithdrawDisposition).length() > 0
}
