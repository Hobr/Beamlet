# Parent acceptance and commit plan

## Acceptance

Parent read the complete independent recheck from run cb73e688-81ea-44ed-bcd2-538f32d06380,
preserved here as research/recheck-report.md. F1–F3 are resolved; no remaining
product blocker was found. Parent accepts the implementation against AC1–AC7
within the verification scope below. This is implementation acceptance, not a
claim of physical-host, paid-provider or power-cut acceptance.

| Criteria | Evidence |
| --- | --- |
| AC1 | Core dependencies Harness/Jason only, no Application callback or effects; isolated Core10 and no-start Core10+Agent5 pass |
| AC2 | Storage facade retains canonical envelope/digest ownership; independent baseline comparison passes map/list depth31/32/33 decode/reduce/replay vectors; malformed inherited source vectors refused |
| AC3 | Source-bound incremental accumulator; first-error/read-stop baseline parity; exact byte vectors at 1048575/1048576/1048577 including escapes/UTF-8; existing fork/context assertions retained |
| AC4 | Actual Server/Durable call sites use Decision; reply/resume/fork classifications inspected against replaced expressions |
| AC5 | Current focused Core10+Agent109 pass; final-fix PostgreSQL78 saved logs inspected; existing assertions unchanged; initial broader evidence below |
| AC6 | Transaction/CAS, preflight vs committed projection, and fixed-request execution ownership preserved; durable recovery/fork/history suites pass |
| AC7 | Agent and backend build dependencies include Core; normal/backend warning-fatal compile pass; app docs and backend specs synchronized |

Initial extraction gates: umbrella512 passed/37 excluded; named35 passed/514
excluded; copied release, two-process durable e2e, Sobelow, catalogue, compile,
format, Credo and Dialyzer passed. These broader gates were not rerun after F1–F3.
Final-fix gates: focused Core10+Agent109, no-start10+5, isolated Core10,
PostgreSQL78, normal/backend compile, format, strict Credo and existing-PLT
Dialyzer passed. Independent recheck freshly repeated focused/no-start tests,
compile/format/strict Credo/Dialyzer and four differential/adversarial probes;
PostgreSQL final-fix logs were inspected rather than rerun. No changed risk
required repeating releases/distributed/e2e. Historical/current differing tool
schema pure coverage remains limited; historical catalogue selection was inspected.
No forced PLT rebuild or physical-host/provider/power-cut validation is claimed.
See implementation-report.md, fix-report.md and recheck-report.md for commands/logs.

## Spec synchronization

Applied trellis-update-spec. Backend agent-durable.md retains its seven-section
contract and now records pure signatures, normalized source fields, depth roots,
first-error/read-stop behavior, precise byte limits, error matrix and required
regressions. Directory/index/app docs describe the actual eleven-app boundary.
No product code changed during parent acceptance/spec synchronization.

## Approved work commit

User confirmed the proposed commit and finish flow with “行”.

`refactor(agent): extract pure agent core`

Include the entire task-owned extraction as one coherent work commit:

- apps/beamlet_agent_core/ (manifest, formatter, README, four modules and tests)
- apps/beamlet_agent/README.md and mix.exs
- apps/beamlet_agent/lib/beamlet/agent/{context_builder,durable,reducer,server}.ex
- apps/beamlet_agent/test/beamlet/{core_adapter_test,context_read_order_test}.exs
- root mix.exs
- .trellis/spec/backend/{agent-durable,directory-structure,index}.md
- .trellis/tasks/10-18-agent-core-extraction/ (planning, manifests, task metadata and research evidence)

All inventoried paths belong to this task's parent/child edits; no unrelated dirty
path was identified. Existing index state was preserved until approval. Stage the
listed final working-tree versions, including these acceptance
and spec updates. Do not commit a stale staged snapshot. Do not amend or push.
After the approved work commit, finish-work archives this task and records the
journal as separate bookkeeping commits. Step10 is complete only after that flow.
