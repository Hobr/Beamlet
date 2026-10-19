# Final verification

## Candidate and retained scope

Verified the complete typespec change against base commit `7ccec0674d5bae1db7ac58b3d5336a88516b5bea`, using Elixir 1.20.4 / OTP 29.1.2. This report records executed results, not new executions after documentation cleanup.

At the user's request, intermediate worker reports, generated inventories, temporary acceptance probes, raw/compressed logs and stage evidence directories were removed before commit. The retained task records are the approved PRD/design/implementation plan, context manifests, original audit baseline, compact function inventory, per-warning disposition and this final report. The coverage inventory is reproducible with `elixir scripts/quality/check-contracts.exs --inventory`. Detailed raw logs are no longer retained in the repository; the results below summarize the previously executed checks.

## Semantic review

The independent review corrected an annotation defect: `Operation.new/1` accepts bounded scalar/list metadata, while its original type required a map. The owner-local recursive `Beamlet.Actions.data()` now represents ordinary payload, capability, environment and metadata data accurately. Runtime validation was not changed.

Direct review covered:

- Actions constructor/validator clauses, empty credential/claim map associations, Result identity/source semantics, pre-admission Execution states and Handler context against Worker callback construction.
- Harness tagged replies, invocation/request fields, catalogue/batch conversion, provider settings and malformed-input fallbacks. Typespec cannot encode exact literal string keys, UTF-8, UUID spelling, byte/depth bounds or all field relationships; existing runtime checks remain authoritative.
- Foundation Transaction's function/Ecto.Multi overloads and input/output type variables; domain Records generic relationships, rollback/error handling and narrow exception recognition.
- Runtime durable/non-durable and initialization states, Worker envelopes, Agent Server restored/child/subscriber states, Loader fallbacks, Core arbitrary-input validators and Storage inheritance accumulators.
- All 68 baseline and nine additional unmatched-return findings, with the individual dispositions retained in `return-dispositions.md`.

Two unreachable alternatives and one private helper used only by an unreachable alternative were removed after examining every callee clause and caller. Proof is retained in the disposition document. Explicit discards preserve effects and exceptions, terminal immutability and existing best-effort cleanup; they do not infer confirmed cancellation or repair business behavior.

The AST audit compared all 148 production sources to the base commit after stripping contract attributes, normalizing alias placement and explicit discards, and allowing only those proved dead-code rewrites. It found no other runtime differences. Changed PO/POT files were compared after stripping only source-reference lines: msgids, translations and metadata were unchanged. No dependency manifest, existing test assertion or GitHub workflow changed.

Five standalone acceptance probes passed: valid empty maps and scalar/list metadata; representative arbitrary bad inputs; exact Model request/invocation/reply key rejection; JSON credential/positive claims validation; and compiled optional-map association presence. Probe files were intermediate artifacts and have been removed as requested. Permanent checker regressions remain in `scripts/quality/check-contracts-test.exs`.

## Executed results

All commands ran from the umbrella root. Tests used seed631927 and privately provisioned PostgreSQL over a Unix socket. PostgreSQL and temporary E2E datasets were stopped/removed after verification.

| Check | Result |
| --- | --- |
| `elixir scripts/quality/check-contracts.exs --inventory` | 148 files, 13 apps, **1345/1345** identities covered, 0 missing/errors, no exemptions |
| `elixir scripts/quality/check-contracts-test.exs` | **40 passed** |
| `mix format --check-formatted` | Exit0 |
| `mix compile --warnings-as-errors` | Exit0 |
| `mix test --seed 631927` with PostgreSQL enabled | **552 passed /37 excluded** |
| Named VM `mix test --only distributed --seed 631927` | **35 passed /554 excluded** |
| `bash scripts/deployment/durable-e2e.sh` | Two phases, each **1 passed /2 excluded** |
| `mix credo` and `mix credo --strict --all` | Exit0, no findings |
| Default enhanced `mix dialyzer` | **0 errors, 0 skipped, 0 unnecessary skips** |
| Isolated fresh project PLT analysis and post-review reanalysis | **0 errors, 0 skipped, 0 unnecessary skips** |
| `mix gettext.extract --check-up-to-date` | Exit0 |
| `mix sobelow` | Exit0 |
| `mix xref graph --format cycles` | Exit0; six existing intra-application cycles, not a zero-cycle claim |
| Actual `contracts-test` and `contracts` pre-commit hooks | Pass |
| Public/private spec-removal CLI mutations | Exit1 as expected |
| Actual check-local failure-propagation shims | Both contract command failures propagate exit23 before any Mix invocation |
| AST/catalogue parity and whitespace checks | Pass |

Ordinary executed counts: Harness35, Actions28, I18n15, Foundation17, Core10, Actions Storage17, Runtime66, Agent Storage64, Agent109, Node78, Server15, Web73, CLI25. PostgreSQL cases actually executed in the domain suites; they were not counted from excluded cases. Named distributed executed counts: Runtime7, Node20, Server2, Web5, CLI1. Other apps had no selected distributed tests.

## Acceptance mapping

- AC1: complete public/private/delegate/macro/template coverage. Initial1346 to final1345 is solely the removed unreachable helper; no ordinary private function is exempted.
- AC2: accurate owned types, valid empty map and metadata correction, preserved legitimate errors/intermediate states and explicit JSON expressiveness limits.
- AC3: Model/Tool/Handler callbacks reviewed against actual implementations and owning tests.
- AC4: all warning dispositions reviewed; enhanced existing/fresh-project analysis clean without ignores or application exclusion.
- AC5: permanent checker positive/negative fixtures and actual local hook/integration wiring verified.
- AC6: compiler, tests and static checks above passed; behavioral parity reviewed. LSP remains inconclusive as described below.
- AC7: backend typespec guidelines and index/quality documentation describe actual conventions and local commands.

## Limits and historical failures

The fresh project/dependency PLT was built with `MIX_BUILD_PATH=_build/contracts-final-fresh`, reusing the existing `.nix-mix` core cache. Dialyxir checked/refreshed six core modules, copied the494-module core PLT and added1735 modules to the new project PLT. This was not a from-zero Erlang/Elixir core cache build. The task-owned isolated build directory was removed during final cleanup after the result was recorded.

Explicit parent-session LSP batches used all148 paths, concurrency16 and waitMs1000: **1 file confirmed clean, 147 timed out**, with no findings returned. An earlier directory probe was capped at100 and all timed out. No whole-project LSP-clean claim follows.

Local peer VMs/E2E are same-host evidence, not physical-host, power-cut or live paid-provider acceptance. The entire release-building `check-local.sh` was not rerun: its contract-command wiring and failure propagation were exercised separately, alongside the explicit final commands above.

Historical initial runs without PostgreSQL configuration failed; later provisioned runs passed. The first failure-propagation shim used unavailable `/bin/bash` and exited126; corrected `/usr/bin/env bash` shims proved exit23 propagation. The first AST audit omitted callback attributes from normalization and failed; corrected normalization passed. These failures are not represented as successful runs. Raw and duplicate intermediate files were removed at the user's request, without changing production code or rerunning unrelated tests solely for cleanup.
