# Spec Structure and Evidence Design

## Approach

Use one owner for this small documentation pass. Keep the existing backend
directory as the Rust workspace/scaffold entry point, and add a Console layer
because that is where meaningful implemented behavior exists. Do not create
packages, child tasks, or a domain model merely to fill template categories.

Current source reads are authoritative. The pi-lens project graph reports an
older commit and incomplete coverage; it cannot establish the current
architecture. CodeGraph supplied current Console bodies, supplemented by direct
source reads and Git-tracked inventory. No graph installation is needed.

## Proposed Final Spec Tree

```text
.trellis/spec/
  index.md
  backend/
    index.md
    directory-structure.md
    quality-guidelines.md
  console/
    index.md
    event-loop.md
    error-handling.md
  guides/
    index.md
    code-reuse-thinking-guide.md
    cross-layer-thinking-guide.md
```

This is a proposed documentation layout, not a product-code reorganization.

## Topic Ownership

| Document | Responsibility |
| --- | --- |
| Root index | Route by edited code; separate current code from future plans. |
| Backend index | Scope of existing Rust scaffolds and missing backend systems. |
| Directory structure | Workspace membership, library/app boundaries, inheritance. |
| Quality guidelines | Existing format, lint, test, license, and build entry points. |
| Console index | Route Console changes to its implemented behavior guides. |
| Event loop | Input, typed events, App mutation, rendering, task lifecycle. |
| Console errors | color-eyre propagation and actual terminal cleanup behavior. |
| Guides index | Route cross-package and reuse decisions without generic essays. |
| Reuse guide | Existing shared library versus application-local Console code. |
| Cross-layer guide | Current event flow and manifest/build-package boundaries. |

Keep rules at one owning location and link from indexes rather than duplicating
the same commands and facts across every file. Short source examples should
illustrate an actual local pattern, not fill a quota.

## Template Removal and Relocation

Remove backend/database-guidelines.md and backend/logging-guidelines.md:
no product database/migration or logging setup exists. Record that absence
briefly in the backend index and add detailed guidelines only when source
exists to support them.

Replace backend/error-handling.md with console/error-handling.md. There is
source-backed application error behavior in Console, but no implemented shared
library/backend error contract. Update every live spec index and reference.
Preserve archived task records as history rather than rewriting their scope.

Rewrite the generic guides using Beamlet examples. Remove upstream Trellis
release/template scenarios and TypeScript payload examples that do not describe
this product. Do not modify the .trellis/scripts/ implementation they discuss.

## Evidence and Non-Claims

Use research/source-inventory.md to select source references. The Console's
unbounded channel and discarded background JoinHandle are scaffold limitations,
not approved patterns for future durable work. Terminal restoration on a
returned Result is not proof of panic-safe cleanup.

The library add test is only a scaffold example; it does not establish backend
test coverage. Root dependency declarations, Nix package definitions, and hook
commands do not prove runtime support or passing builds.

The archived Rune-first decision may be linked as future context, explicitly
separated from present implementation. Detailed replay, schema, permission,
and cancellation prescriptions do not belong in these current-state specs.

## Compatibility and Validation

Retaining the backend index preserves the existing discovery entry point.
New root/Console indexes provide focused routing. The current
common.packages_context._scan_spec_layers scans immediate spec subdirectories
except guides, so Console discovery needs no runtime change. Validate discovery
after the rewrite and search all live references to removed paths.
The archived Rune task currently refers to backend/index.md, which is retained.

Only documentation and task artifacts change. A rollback restores the coherent
spec tree and indexes together; it must not touch product files or invoke
destructive Git cleanup.
