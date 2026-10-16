# Independent Harness and Concrete Providers

## Goal

Provide backend-neutral Tool/model/context interfaces plus a real compatible model adapter and constrained read-only workspace Tool.

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
The user approved the complete parent/child plan on 2026-10-16 ("批准").
Implementation is authorized once this child's prerequisite gates pass; only the
currently activated child is an implementation target.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Dependencies

No implementation dependency on child 1; default execution follows its gate to preserve one-writer sequencing. Child 3 needs both children complete.

## Requirements

1. Own parent R1/R4/R7 Harness portions and AC1/AC5/AC6. Harness must not import/depend on Actions/Runtime/Agent.
2. Provide deterministic native model/Tool fixtures and neutral progress/cancellation hooks.
3. Implement the parent-design non-streaming text Chat Completions/function-tool subset with executor-local trusted profiles, exact Req 0.7.5 and direct Jason dependency.
4. Implement explicit catalogue schema subset and complete-batch validation, read-only workspace file invocation, finite HTTP/text/context data handling and safe error normalization.

## Acceptance Criteria

- AC1: Native Harness contracts/tests run without Actions/Runtime/Phoenix; descriptors need no model key or workspace process on authority.
- AC2: A local socket HTTP fixture verifies request path/auth/body/tool IDs and normalized replies. Refusal/incomplete/malformed/duplicate-call/oversized responses fail explicitly; 429/500/timeout and redirects cause no second request.
- AC3: Response limits apply to success and error paths; callback overflow is not accepted as a valid partial reply, and unexpected encoding/TLS failures fail closed.
- AC4: Workspace tests cover valid/empty/long UTF-8 file reads, traversal/absolute/NUL paths, symlink ancestors/leaves, directories/nonregular leaves, invalid UTF-8, descriptor cleanup and explicit truncation.
- AC5: Read-only confinement limitations and supported provider/schema subset are documented; no claim of adversarial race-free sandboxing or full OpenAI compatibility.

## Out of Scope

All parent exclusions apply. This child owns only its named seam; no unrelated
scaffold/UI/provider/runtime refactor. Parent criteria referenced above remain
authoritative even when local AC numbering differs.
