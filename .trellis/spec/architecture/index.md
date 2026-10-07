# Architecture Specification

Status: reviewed target contract, approved 2026-10-07. Specification revision: architecture-v1.

This layer guides the generic Elixir/OTP runtime and its consumers before implementation. API notation and payloads below are target contracts; they do not claim that modules, storage backends or platforms are implemented.

## Read Order

| Document | Owns |
|---|---|
| [Glossary](./glossary.md) | Canonical domain language |
| [Boundaries](./boundaries.md) | Logical modules, dependency direction, generic/domain separation |
| [Computation and Effects](./computation-and-effects.md) | Authoring, identities, records, public API and reply delivery |
| [Authority and Recovery](./authority-and-recovery.md) | Atomic commands, receipts, epochs, attempts and failures |
| [Capability Composition](./capability-composition.md) | Scope, generations, resolution and external execution orchestration |
| [Lifecycle and Archives](./lifecycle-and-archives.md) | Continuation, suspend/resume, stable branches, ETF and compatibility |
| [Platforms and Trust](./platforms-and-trust.md) | Endpoint roles, secure edges and the trusted-member premise |
| [Decisions](./decisions.md) | Rationale, alternatives and deferred implementation gates |

Read the owner of a changed contract and follow its Tests Required section. Do not duplicate decoders, status interpretation or authorization policy in UI consumers.

## Requirement and Scenario Coverage

Scenario numbers also map to the originating acceptance criteria AC1-AC19.

| Requirement | Reviewed behavior | Scenario / assertion owner |
|---|---|---|
| R1 | Generic computation foundation | [S1](./boundaries.md#s1), [S6](./boundaries.md#s6) |
| R2 | Agent uses capabilities without Effect knowledge | [S1](./boundaries.md#s1), [S2](./computation-and-effects.md#s2) |
| R3 | Execute remotely and recover when the host is unavailable | [S3](./authority-and-recovery.md#s3) |
| R4 | Explicit lifecycle semantics | [S5](./lifecycle-and-archives.md#s5) |
| R5 | CLI/TUI/Desktop/Web/Android/Server Node targets | [S15](./platforms-and-trust.md#s15) |
| R6 | Acknowledgement, failure and uncertainty contracts | [S4](./authority-and-recovery.md#s4) |
| R7 | Discoverable maintained specifications and reviewed publication | [S7](#s7), [S8](#s8) |
| R8 | Explicit resumable state progression | [S2](./computation-and-effects.md#s2) |
| R9 | Dynamic scoped capability composition | [S9](./capability-composition.md#s9) |
| R10 | Designated authorities and cluster durability | [S10](./authority-and-recovery.md#s10) |
| R11 | Operation-declared recovery | [S11](./authority-and-recovery.md#s11) |
| R12 | Immutable intent, late provider resolution | [S12](./capability-composition.md#s12) |
| R13 | Stable-boundary fork with independent future identity | [S13](./lifecycle-and-archives.md#s13) |
| R14 | Historical inspection and external pre-execution review | [S14](./capability-composition.md#s14) |
| R15 | Configurable roles on BEAM hosts | [S15](./platforms-and-trust.md#s15) |
| R16 | Operator-managed trusted cluster | [S16](./platforms-and-trust.md#s16) |
| R17 | Portable archive/import as a new branch | [S17](./lifecycle-and-archives.md#s17) |
| R18 | Constrained, versioned ETF data | [S18](./lifecycle-and-archives.md#s18) |
| R19 | Suspend new work, retain admitted outcomes | [S19](./lifecycle-and-archives.md#s19) |

## Contract Status and Governance

- **Reviewed target**: required behavior and invariants accepted in the architecture review.
- **Implementation recommendation**: a concrete approach that must pass its stated feasibility gate.
- **Deferred**: explicitly excluded work or future validation, never an implied supported feature.

Update the owning contract and scenario before changing behavior. Keep stable requirement/scenario identifiers. Supersede a decision with a new linked entry rather than erasing rationale. Version persistent formats independently of package releases; a pre-release label does not permit silent reinterpretation of saved history.

Existing backend/frontend scaffold guides remain scaffolding until real code conventions exist. This architecture layer does not invent those conventions.

## Initial Scope and Implementation Gates

The initial contract uses explicit state, immutable intents, logical identities, trusted nodes and stable-boundary branches. It excludes external undo/Saga compensation, exactly-once execution claims, in-flight fork, malicious-member containment and built-in approval workflows.

One authority group is the initial implementation ceiling. Ra is a proposed storage target, subject to the toolchain/persistence gate in [Decisions](./decisions.md). Codec budgets and real-device/network support require prototype validation. No runtime tests were run to publish this document baseline.

## Quality Check

Run from the repository root:

~~~bash
python3 .trellis/scripts/get_context.py --mode packages
git diff --check
git diff --cached --check
~~~

Validate the published library:

~~~bash
python3 - <<'PY'
import re
from pathlib import Path
root = Path(".trellis/spec/architecture")
files = list(root.glob("*.md"))
assert len(files) == 9
index = (root / "index.md").read_text()
for n in range(1, 20):
    assert f"| R{n} |" in index, n
for path in files:
    body = path.read_text()
    assert body.endswith("\n") and all(s == s.rstrip() for s in body.splitlines()), path
    for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", body):
        if target.startswith(("http://", "https://")):
            continue
        filename, _, anchor = target.partition("#")
        destination = (path.parent / filename).resolve() if filename else path.resolve()
        assert destination.is_file(), (path, target)
        if anchor:
            assert f'id="{anchor}"' in destination.read_text(), (path, target)
print("Architecture files, requirement index, local references and scenario anchors verified.")
PY
~~~

A documentation check proves neither executable behavior nor platform/backend support. Future implementations must satisfy each owner's assertion matrix using real runtime tests.

<a id="s7"></a>
### S7 — Maintained Contract Library

Given a future engineer or agent, the index must identify the owner and test scenario for every R1-R19 requirement. Local references and anchors resolve; implementation recommendations remain labeled; the normative contract never asserts an unverified release/runtime guarantee.

<a id="s8"></a>
### S8 — Final Planning Review Gate

The requirement/design/publication artifacts and deferred gates must be presented before execution. A subsequent explicit user approval authorizes task activation/publication; approval of an earlier individual design choice does not replace that final review. This baseline passed that review on 2026-10-07.
