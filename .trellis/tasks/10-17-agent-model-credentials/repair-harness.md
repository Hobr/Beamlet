# F1 Harness repair

F1 is repaired within Harness source/tests. Initial `check-report.md` and all other component/task-state/spec/deployment files are untouched. This report is the only task artifact written. No staging, commits, branches, dependency changes, live/paid calls, or unchanged umbrella/distributed/release gates.

## Root cause and chosen handling

`Model.validate_reply/2` and `OpenAICompatible.normalize/2` encoded the complete incoming reply before semantic validation. Jason returns error tuples for many unsupported terms, but its improper-list traversal raises `FunctionClauseError`, including nested improper lists. The direct public callers therefore received an exception instead of `{:error, :invalid_reply}`.

Each owning module now uses a small private encoding function that rescues **only `FunctionClauseError` around `Jason.encode/1`**, returning the existing `:invalid_reply` error. Catalogue validation remains first; whole-envelope encoding and byte checks retain their existing position, ceilings and error precedence. This does not rescue entire provider/semantic validation paths, alter legitimate oversize replies to invalid replies, truncate data, or depend on Handler interception. OpenAI wire parsing remains entirely inside its adapter. The adapter module documentation now describes Agent-owned invocation configuration and credentials.

An immediate blast-radius probe found the same exception family in catalogue schemas with improper `required` or primitive `enum` lists. Both reply APIs validate the catalogue first, so those malformed inputs also escaped the safe boundary. `Arguments.schema?/1` now checks those lists are proper before enumeration, preserving supported schema semantics and returning the existing catalogue errors. Evidence: `catalogue-probe.exs`, `catalogue-before.log`, and `catalogue-final.log` in the log directory below. Direct Catalogue construction/validation, neutral reply/request and OpenAI normalization regressions cover this narrow extension.

## Changed paths

- `apps/beamlet_harness/lib/beamlet/harness/model.ex`: encoding-only malformed reply handling.
- `apps/beamlet_harness/lib/beamlet/harness/models/open_ai_compatible.ex`: encoding-only direct normalization handling and ownership documentation.
- `apps/beamlet_harness/lib/beamlet/harness/arguments.ex`: proper-list validation for schema required/enum values.
- `apps/beamlet_harness/test/beamlet/model_test.exs`: four new direct boundary tests.
- `.trellis/tasks/10-17-agent-model-credentials/repair-harness.md`: this report.

## Regression coverage and results

Four added tests cover improper call-list tails, nested improper argument values, improper OpenAI envelopes/choices/tool calls/nested metadata, improper catalogue schema lists, and complete neutral/OpenAI reply envelopes exactly at 1,048,576 bytes and one byte over. Valid neutral tool replies and OpenAI text replies still succeed. Exact-limit replies succeed; one byte over still yields `:response_limit`. The unchanged request-envelope regression exercises the combined catalogue/history request cap; all existing history, schema, whole-batch, HTTP request/body/auth, one-attempt/overflow/encoding/TLS and workspace tests ran in the focused suite.

All Mix/Elixir commands used `ERL_FLAGS='+S 2:2'`. Logs and scratch scripts are under **`/tmp/beamlet-repair-harness-631927/`**. Separate failed/intermediate logs were preserved:

| Command/scope | Result | Log |
| --- | --- | --- |
| Root `mix test apps/beamlet_harness/test/beamlet/model_test.exs --seed 631927`, before repair | 5/7 passed, 2 failed with original Jason FunctionClauseError | `tests-before.log` |
| Catalogue probe before repair (`MIX_ENV=test mix run --no-start .../catalogue-probe.exs`) | Required/enum improper lists each raised at Catalogue, neutral and OpenAI boundaries | `catalogue-before.log` |
| Root `mix format` with the four explicitly named touched Elixir files | Passed | `format.log` |
| Root `mix test apps/beamlet_harness/test/beamlet/model_test.exs --seed 631927`, initial repair | 8 passed | `tests-focused-final.log` |
| Harness app `mix test --seed 631927`, initial repair | 35 passed | `tests-suite-attempt1-passed.log` |
| First root strict Credo attempt with repeated `--files-included` options | Failed: one length-in-guard warning; actually scanned 82 files | `credo-attempt1-failed.log` |
| Final root `mix credo --strict 'apps/beamlet_harness/{lib,test}/**/*.{ex,exs}'` | 14 files, 69 checks, no issues | `credo-final.log` |
| Final Harness app `mix test --seed 631927` | **35 passed**, 6.3 seconds; TCP/TLS fixtures ran, expected self-signed certificate rejection notices | `tests-suite-final.log` |
| Final root `mix format --check-formatted` with four explicitly named touched Elixir files | Passed | `format-check-final.log` |
| Final Harness app `mix compile --warnings-as-errors` | Passed | `compile-final.log` |
| Final root `mix run --no-start --no-compile /tmp/beamlet-repair-harness-631927/dialyzer-harness.exs` | Dialyzer analysis of all **11 Harness BEAM modules**, **0 warnings**, existing umbrella dependency PLT, no PLT check/refresh | `dialyzer-final.log` |
| Original `/tmp/beamlet-review-probe.exs`, rerun with `MIX_ENV=test mix run --no-start --no-compile` | All F1 vectors return safe errors; F3 still reproduced and remains next owner's work | `probe-final.log` |
| Catalogue probe after repair | All six prior raised cases return `:invalid_catalogue` | `catalogue-final.log` |
| `git diff --check` / `git diff --cached --name-only` | Passed / empty | `diff-check-final.log` / `staged-files-final.log` |

The Credo warning was resolved by using explicit tail-recursive proper-list matching instead of the length guard. Compilation, full focused suite and Dialyzer were rerun afterward. The first passing Dialyzer analysis is preserved separately in `dialyzer-attempt1-passed.log`. The scratch Dialyzer script calls `:dialyzer.run/1` against the already compiled Harness modules and existing `_build/dev/dialyxir_erlang-29.1.2_elixir-1.20.4_deps-dev.plt`, printing all warnings and failing on any warning; this is focused analysis, not a full umbrella `mix dialyzer` or PLT refresh claim.

## Residual risks and follow-up

No remaining F1 blocker found in the touched boundaries. F2 and F3 are deliberately unmodified and remain assigned to subsequent serial owners; the original review probe still demonstrates F3. Main owns the fresh integrated recheck and later full gates. The pre-repair 138 ordinary/9 distributed integration result is historical evidence only. No complete LSP cleanliness, refreshed PLT, distributed/release validation, physical-host acceptance, or live model execution is claimed by this repair.
