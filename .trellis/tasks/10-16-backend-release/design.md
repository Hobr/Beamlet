# Backend CLI, Release and Multi-machine Acceptance — Design

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
This child is planning only. The parent final summary must be approved before
activation; no product code or implementation dispatch is authorized yet.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Dependencies and Ordering

BLOCKED until children 1–3 pass their gates and publish actual interfaces. Parent owns final cross-child AC sign-off and remains incomplete without required physical-host evidence.

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

Physical run uses at least two distinct hosts; client A may share one host, but
authority B and executor C must differ. Record actual host/node identity and
execution evidence. Same-host :peer tests are useful automation, not physical
acceptance. If external machines are unavailable, complete all local deliverables,
leave physical gate pending and request only the missing access/instructions then.

## Integration Ownership

Review parent AC1–AC12 against all child handoffs; attach exact validation evidence.
Do not reimplement loop/provider/scheduler policy to make the demo pass.
Any defect goes to its owning child seam for a scoped fix and focused recheck.

## Compatibility and Rollback

Replace generated stubs only within this child. No stable domain API exists yet;
preserve unrelated Web behavior. Deploy matching builds to peers. On failed gate,
stop and revise scoped changes; no reset of unrelated work or automatic business
replay. Record actual checks and limitations for the next child.
