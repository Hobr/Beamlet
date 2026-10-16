# Independent Harness and Concrete Providers — Design

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
This child is planning only. The parent final summary must be approved before
activation; no product code or implementation dispatch is authorized yet.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Dependencies and Ordering

No implementation dependency on child 1; default execution follows its gate to preserve one-writer sequencing. Child 3 needs both children complete.

## Owned Design

Implement parent design §§4–5 and research
`../10-16-distributed-agent-mvp/research/provider-workspace-release.md`.
Suggested groups: native Model/Tool behaviours and request/reply/call/environment
values, Catalogue/Arguments/Context, Models.OpenAICompatible, Tools.WorkspaceRead
and deterministic test providers. Provider-specific modules own HTTP wire details;
native contracts contain no OperationRef/resource-pool keys.

Use executor-resolved profile ID → endpoint/model/credential settings. Only
configured URLs/modules/providers are executable. Model strings never become atoms.
Read final complete replies only, validate finish reason/refusal/call IDs/arguments,
and validate an entire batch before callers can dispatch any member.

Req callback accumulates bounded bytes on all statuses and marks overflow in
response-private state. Explicit retry/redirect false, identity encoding/raw
bounded processing, safe TLS and operation-independent transport timeouts.
Test actual resolved Finch/Mint behavior; pinned Req is not a transitive lock.

Workspace root is local deployment data. Inspect relative path components without
normalizing away traversal, reject symlinks/nonregulars, read bounded descriptor
content, preserve UTF-8 and always close. Document trusted-tree/TOCTOU/hardlink/
mount limitations; deployment must control backing writers. No shell/native helper.

## Consumer Handoff

Record catalogue, model messages/replies/tool-call errors, context hooks,
environment descriptors and invocation options. Child 3's adapter maps these
native contracts, never makes provider authors implement runtime handlers.

## Compatibility and Rollback

Replace generated stubs only within this child. No stable domain API exists yet;
preserve unrelated Web behavior. Deploy matching builds to peers. On failed gate,
stop and revise scoped changes; no reset of unrelated work or automatic business
replay. Record actual checks and limitations for the next child.
