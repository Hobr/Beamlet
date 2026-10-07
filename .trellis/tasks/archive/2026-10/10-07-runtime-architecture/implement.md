# Specification Publication Plan

Status: approved on 2026-10-07; specification publication and document checks complete.
Task: .trellis/tasks/10-07-runtime-architecture.
Inputs: [PRD](./prd.md), [design](./design.md), [glossary](./GLOSSARY.md), [research](./research/initial-evidence.md), [authority research](./research/authority-storage.md).

## Scope and Ownership

Deliver one integrated architecture/specification library. All files below describe the reviewed target contract, not an implemented runtime. No Mix project, dependency installation, backend, Agent, frontend or deployment is created in this task.

Implementation/check responsibilities run sequentially in the main session under the supplied AGENTS.md tool mapping. Keep Trellis context manifests valid without changing platform configuration or creating worker worktrees.

Preserve existing README.md, flake.lock, scaffold guideline and bootstrap-task changes. Add no unrelated cleanup.

## Ordered Work

- [x] Review gate: present the latest architecture, requirements, limits and deferred validation to the user.
- [x] After a subsequent explicit approval, activate this task with task.py start.
- [x] Publish spec/architecture/index.md with status/read order and coverage.
- [x] Publish glossary.md from the resolved task glossary.
- [x] Publish boundaries.md for generic/domain separation and acyclic logical responsibilities.
- [x] Publish computation-and-effects.md for complete data/authoring/control interface contracts.
- [x] Publish authority-and-recovery.md for atomic commits, receipt semantics, epochs, attempt/outcome/retry rules and fault cases.
- [x] Publish capability-composition.md for Scope descriptors, live generations, late resolution, matching and external execution orchestration.
- [x] Publish lifecycle-and-archives.md for stable boundaries, continuation, suspension, branch identity, archive/version and ETF validation.
- [x] Publish platforms-and-trust.md for every requested surface, role selection, edge authorization and validation gates.
- [x] Publish decisions.md with concise rationale and rejected alternatives; retain the storage backend recommendation as proposed/gated.
- [x] Run the whole-library consistency, boundary/scenario, link and manifest checks below.
- [x] Repair only specification/task issues, then repeat the affected check.
- [x] Present the reviewed result and remaining implementation gates accurately.
- [x] Commit only the owned task/spec changes in the Phase 3.4 work batch.

The finish-work workflow archives the accepted document task and records its session journal after the work commits. These are bookkeeping operations, not unfinished runtime implementation.

## Contract Completeness Checklist

- [x] Agent definitions/facades depend only on business state, Invocation and Reply.
- [x] Define ready/waiting/finished continuation data and the small step-result vocabulary.
- [x] Identify immutable intent versus mutable observations/control records.
- [x] Specify state/input/Effect atomicity, stable command keys, key conflicts and commit_unknown.
- [x] Scope ownership, host epochs and attempt permissions do not serialize PIDs/closures.
- [x] Known outcome, unknown evidence, non-execution evidence and canonical reply are distinct.
- [x] Retry preserves request meaning, provider compatibility and deduplication domain/retention.
- [x] Duplicate/late results are auditable without repeated consumption.
- [x] External pre-execution coordination controls the real path with no automatic bypass or built-in approval states.
- [x] Suspended Runs can retain admitted outcomes and reject new advancement/grants.
- [x] Stable fork/archive excludes unsettled completion delivery and live source queues.
- [x] Import creates a suspended new branch, reconstructs only its data continuation, and verifies code/resources before activation.
- [x] ETF supports a declared bounded data profile, full-consumption decoding and schema validation without executing archive code.
- [x] Trusted-node premise, external client authorization and resource permission are explicit.
- [x] Source/child resource references do not imply automatic graph/environment cloning.
- [x] Every confirmed R/AC is covered; every proposed/deferred implementation item is labeled.

## Coverage Map

| Requirements | Primary specification |
|---|---|
| R1, R2 | boundaries.md; computation-and-effects.md |
| R3, R6, R10, R11 | authority-and-recovery.md |
| R4, R13, R17, R18, R19 | lifecycle-and-archives.md |
| R5, R15, R16 | platforms-and-trust.md |
| R7 | index.md; decisions.md |
| R8 | computation-and-effects.md |
| R9, R12, R14 | capability-composition.md |

Each AC1-AC19 gets a linked scenario/check in the index and its owning contract. Avoid claiming runtime tests passed; this task checks specifications and future acceptance scenarios.

## Validation Commands

Run from the repository root:

~~~bash
python3 .trellis/scripts/task.py validate .trellis/tasks/10-07-runtime-architecture
python3 .trellis/scripts/get_context.py --mode packages
git diff --check
git diff --cached --check
~~~

The package discovery output must include the new architecture layer after publication. Both JSONL manifests must contain existing real spec/research paths, never future/missing files or product code.

Run this documentation-only check after publication:

~~~bash
python3 - <<'PY'
import json
import re
from pathlib import Path

repo = Path.cwd()
task = repo / ".trellis/tasks/10-07-runtime-architecture"
spec = repo / "spec/architecture"
files = list(task.rglob("*.md")) + list(spec.rglob("*.md"))
assert spec.joinpath("index.md").is_file()
for path in files:
    body = path.read_text()
    assert body.endswith("\n"), path
    assert all(line == line.rstrip() for line in body.splitlines()), path
    for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", body):
        if target.startswith(("http://", "https://")):
            continue
        local = target.split("#", 1)[0].strip("<>")
        if local:
            assert (path.parent / local).resolve().exists(), (path, target)
for name in ("implement.jsonl", "check.jsonl"):
    entries = [json.loads(line) for line in (task / name).read_text().splitlines() if line.strip()]
    assert entries and all((repo / row["file"]).is_file() and row["reason"] for row in entries), name
for number in range(1, 20):
    assert f"R{number}" in spec.joinpath("index.md").read_text(), number
print("Specification links, formatting, manifests and requirement index verified.")
PY
~~~

Then read the diagrams, tables and scenarios as a whole. A link check does not prove semantic correctness.

## Review Passes

1. **Coherence**: vocabulary, reference identities, state transitions, ready continuations, version/profile meanings, source-versus-branch history and acyclic boundaries.
2. **Failure pressure**: trace crashes before/after each commit, ambiguity of lost receipts, worker/owner separation, stale epochs, provider replacement/expired deduplication, minority partitions, suspension races, and portable-import activation.
3. **Scope/simplicity**: no Agent/policy magic, automatic external cancellation, recursive graph copying, custom consensus/serializer/middleware, or unnecessary physical packages.
4. **Status**: distinguish confirmed product semantics, proposed technical refinements, and future prototype/platform gates.

## Future Implementation Gates

Separate future task(s) must prove the storage candidate on OTP 29/Elixir 1.20, its disk/quorum acknowledgement and snapshot behavior, codec/resource bounds, a non-Agent computation across real worker/owner faults, and later Agent/provider/platform integration. The document task neither installs these components nor lowers a guarantee to accommodate them.

The first runtime slice should verify: pure step + capability intent, committed authority/outbox/inbox, one remote provider, explicit retry/unknown, stale-owner rejection, pause/resume, and stable archive round trip. Add Agent and clients after the generic contract holds.

## Rollback

Before commit, review owned paths and existing staged work. Revert only this task's documentation changes if necessary, preserving the original snapshot of unrelated work. After publication, correct/supersede a contract or reverse the owned docs commit through reviewed Git work; do not reset unrelated files or erase previous decision rationale.
