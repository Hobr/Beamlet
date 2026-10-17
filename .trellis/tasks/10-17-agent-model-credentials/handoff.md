# Integration handoff

Integrated candidate ready for fresh independent review. No independent-review
approval is claimed. Full executed commands/counts/logs and AC1–AC8 matrix are in
[verification.md](verification.md); component handoffs retain implementation details.

## Integration-owned changes

- `README.md`: describe immutable Agent binding, trusted registry, removed key_env,
  matching builds and plaintext lifetime.
- `scripts/deployment/README.md`: replace static model profile/key_env deployment
  with local model_providers registrations and explicit provider/config/credentials/
  placement Agent creation. Operator `System.fetch_env!("BEAMLET_CREATION_KEY")` on
  interaction node supplies creation input; provider code has no environment fallback
  and executor needs no provisioned user key. Tool workspace remains local. Explain
  one supported binding, child/peer isolation, no switching, matching-build rollout,
  plaintext copies/no secure erasure and fixture-only HTTP guidance.
- `scripts/deployment/node.example.exs`: authority/executor trusted adapter registration,
  remove model route/static profile, retain executor-local workspace Tool settings.
- `scripts/deployment/check-local.sh`: pin ordinary and named acceptance seed631927.
- `scripts/deployment/check-release.sh` and `check-named-release.py`: extend copied
  eval and named start/RPC/stop coverage from two individual roles to all seven
  role subsets. Preserve closure exclusions, relative config rejection, fixed
  service ports19100/19101 and existing control port0/eaddrinuse fix in rel/env.
- task `verification.md` and this `handoff.md`: actual evidence and residual limits.

## Demonstrated static findings repaired

Strict Credo attempt1 failed; raw log retained. No API redesign or admission/
lifecycle/placement algorithm changes. No compatibility shim or business retry.

Alias/ordering repairs in:
- `apps/beamlet_agent/lib/beamlet/agent/authority_supervisor.ex`
- `apps/beamlet_agent/lib/beamlet/agent/integration/handler.ex`
- `apps/beamlet_agent/lib/beamlet/agent/model_binding.ex`
- `apps/beamlet_agent/lib/beamlet/agent/server.ex`
- `apps/beamlet_node/lib/beamlet/node.ex`
- `apps/beamlet_node/test/beamlet/concurrent_tools_test.exs`
- `apps/beamlet_node/test/beamlet/distributed_test.exs`
- `apps/beamlet_node/test/beamlet/lifecycle_test.exs`
- `apps/beamlet_node/test/beamlet/model_binding_test.exs`
- `apps/beamlet_node/test/beamlet/review_test.exs`
- `apps/beamlet_node/test/support/alternate_model.ex`
- `apps/beamlet_node/test/support/fixtures.ex`
- `apps/beamlet_node/test/support/loop_model.ex`

Complexity/nesting repairs:
- `apps/beamlet_harness/lib/beamlet/harness/model.ex`: extract private config and
  credential predicates and neutral reply semantics; preserve validation order,
  complete reply byte checks and error behavior.
- `apps/beamlet_harness/lib/beamlet/harness/models/deterministic.ex`: extract JSON
  fixture call conversion and pattern-matched fixture reply validation, preserving
  supported text/tool_calls/count/shape checks.
- `apps/beamlet_node/test/support/fixtures.ex`: extract TestModel reply helper to
  reduce nested conditionals; observer/hold and reply behavior unchanged.

Intermediate Credo attempts2/3 findings retained, final strict Credo82 files clean.
Affected rechecks: warning-fatal compile; full umbrella138 ordinary + all9 actual
named distributed; existing-PLT Dialyzer0 errors; root format; rebuilt backend and
copied release. No added source tests were necessary: existing component assertions
already prove integration contracts and all ACs; no test assertions weakened.

Expanded copied release attempt failed because checker still compared entire
comma-separated roles string to a single role. Raw release-final.log preserved;
repaired checker predicates to test membership in split role list. Only affected
release gate rerun (release-attempt3.log), all7 eval/all7 named combinations completed
with startup/RPC/stop and relative-path rejection. No application availability retry
or API fallback was introduced. Existing bounded startup readiness polling retained.

## Results and remaining work

138 ordinary tests passed (Harness31, Actions9, Runtime30, Agent4, Node57, Web7),
9 distributed excluded from ordinary; named Runtime6+Node3 all executed/passed,
138 ordinary excluded. Direct HTTP TCP/TLS and Web CSP ran. Four ephemeral Python
fixture checks passed including incomplete-header deadline and malformed length.
Web production missing-secret failed as expected. Backend has no Web/Phoenix/Plug/
Bandit closure. Format, warning-fatal compile, strict Credo and existing-PLT Dialyzer
passed. No forced PLT refresh or LSP coverage claimed.

No unresolved integration blocker observed. Main session still owns fresh independent
full-diff review, executable spec synchronization and subsequent approved commit/task
workflow. Specs intentionally untouched. No task-state/planning/archive, flake,
dependency/lock, staging/commit/branch changes. Staged diff empty.

Residual limits: same-host evidence only; no physical/live/paid provider acceptance;
only supported text/function subset and one immutable binding per Agent; matching
builds required; transient plaintext process/message copies, no secure-erasure or
administrator-inspection guarantee; generated output absence does not constrain
malicious provider echo. Earlier Agent/Node initial raw failure logs were overwritten
and only excerpts survive, so original root causes cannot be proved from complete
raw evidence. This lane's failure and final-pass logs are separate under
`/tmp/beamlet-integration-631927/`; preserve them before workspace cleanup.
