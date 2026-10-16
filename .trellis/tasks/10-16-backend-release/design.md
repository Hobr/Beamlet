# Backend CLI, Release and Multi-machine Acceptance — Design

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
The user approved the complete parent/child plan on 2026-10-16 ("批准").
Implementation is authorized once this child's prerequisite gates pass; only the
currently activated child is an implementation target.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Dependencies and Ordering

Prerequisites satisfied on 2026-10-16: parent accepted children1–3 scoped
implementation/check gates and published actual handoffs/executable specs. Child3's
final independent86-test gate (seed631927) includes all six distributed cases;
public Runtime admission and bounded lifecycle contracts are accepted. Consume
all three actual handoffs plus operation-runtime/harness-providers/agent-orchestration
specs. Commit/archive bookkeeping remains deferred to final delivery. Parent owns
cross-child sign-off. Physical-host acceptance was cancelled by the user;
no physical execution is claimed.

## Owned Design

Implement parent design §7 and end-to-end checks from §8. Add a thin
Beamlet.Node.CLI facade and small script/examples for named interaction client or
release console/RPC. Commands use actual Agent refs and event credits. Waiting
occurs in client code, not Agent callbacks; output and user input are bounded.

Declare root release entry rooted in Node, verify actual dependency closure, and
supply backend-specific runtime config where supported so default production Web
secret validation remains intact. Test release config before selecting a flag
alternative. Build tooling dependencies are distinct from shipped runtime apps.
Minimal Web startup guard is permitted only when needed to preserve fail-fast,
not for new product UI or relaxing CSP.

Runbook covers one compatible build, long node names/reachable DNS, shared cookie,
trusted-network EPMD and fixed distribution ports, static peers, roles, per-node
provider profile/workspace/model credentials and CA provisioning. Secrets stay on
executor; never embed them in command transcripts/reports. The workspace exposed
to the Tool must be a provisioned allowed-content tree with controlled backing
writers; read-only API does not provide OS isolation.

The user cancelled cross-physical-host acceptance. Independent A/B/C VMs and copied
named-release checks satisfy the revised execution gates. Retain the physical
runbook as an optional deployment resource; do not request hosts or imply physical
evidence from same-host peers. No physical-host run was performed.

## Integration Ownership

Review parent AC1–AC12 against all child handoffs; attach exact validation evidence.
Do not reimplement loop/provider/scheduler policy to make the demo pass.
Any defect goes to its owning child seam for a scoped fix and focused recheck.

## Compatibility and Rollback

Replace generated stubs only within this child. No stable domain API exists yet;
preserve unrelated Web behavior. Deploy matching builds to peers. On failed gate,
stop and revise scoped changes; no reset of unrelated work or automatic business
replay. Record actual checks and limitations for the next child.
