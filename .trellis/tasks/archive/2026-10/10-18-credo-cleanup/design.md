# Design: Credo cleanup for merged durable code

## Boundary

Refactor only: `apps/beamlet_agent`, `apps/beamlet_runtime`, `apps/beamlet_storage`
(production + tests). No schema, migration, transaction, or public function change.
`mix.lock`, deployment scripts and release config stay byte-identical.

## Findings and safe remedy per check

| Check | Count | Remedy | Risk |
| --- | --- | --- | --- |
| `Design.AliasUsage` | 58 | Add top-level `alias` for the repeated `Beamlet.*` prefixes and shorten call sites | low; must avoid alias clashes and ordering issues (`Readability.AliasOrder`) |
| `Refactor.Nesting` | 22 | Extract the inner branch into a private helper or use `with`/`case`; keep each helper a single responsibility | medium; pure extraction, covered by tests |
| `Refactor.CyclomaticComplexity` | 5 | Split the function by outcome into private helpers; keep clause order | medium |
| `Refactor.WithClauses` | 4 | Ensure `with` starts and ends with `<-`; move bare assignments into the body | low |
| `Refactor.RedundantWithClauseResult` | 3 | Remove the trailing assignment that the body repeats | low |
| `Readability.AliasOrder` | 3 | Sort alias groups per Credo's ordering | trivial |
| `Refactor.CondStatements` | 3 | Replace two-branch `cond` with `if` | trivial |
| `Refactor.FunctionArity` | 2 | Group related arguments into a small map/struct *internal* to the module | medium; update private call sites only |
| `Readability.WithSingleClause` | 2 | Replace single-clause `with` by `case` | low |
| `Refactor.UnlessWithElse` | 1 | Rewrite as `if` | trivial |
| `Readability.PreferImplicitTry` | 1 | Drop the explicit `try` | trivial |
| `Refactor.LongQuoteBlocks` | 1 | Split the shared test `quote` into smaller named quote fragments composed by the macro | medium; used by the storage contract suite |
| `Readability.ModuleDoc` | 1 | Add a `@moduledoc` to the test support module | trivial |

Per-file counts are in `research/credo-findings.md`; work file-by-file so a failing
suite localises immediately.

## Guardrails

- No `@dialyzer` or Credo suppression attributes/`# credo:disable-for-*` comments.
- No changes to the public behaviour of `Beamlet.Agent`, `Beamlet.Runtime`,
  `Beamlet.Storage.*`; helpers are `defp`, new modules (if any) are `@moduledoc false`
  private implementation modules inside the same app.
- Test assertions keep their exact values; only structure changes.
- After each app: `mix test apps/<app>/test` (root invocation), then
  `mix credo --strict` to see remaining findings.

## Validation strategy

1. Targeted per-app tests while refactoring.
2. Final full gates from the repo root:
   `mix format --check-formatted`, `mix compile --warnings-as-errors`, full
   `mix test --seed 631927`, storage suite, named distributed suite,
   `mix credo`, `mix credo --strict`, `mix sobelow`,
   `mix gettext.extract --check-up-to-date`, `mix dialyzer`,
   `bash scripts/deployment/durable-e2e.sh`.
3. `git diff --stat` review: production changes must be confined to the three apps;
   `git diff -- mix.lock scripts apps/*/mix.exs` must be empty.
4. Independent `trellis-check` review (spec + diff + gates).

## Rollback

Revert the refactor commit(s). Behaviour is unchanged by construction, so rollback
is a plain `git revert` with no data migration.

## Residual risk

`AliasUsage` fixes in test files can accidentally shadow modules named in `use`
macros; run each test file after editing. `LongQuoteBlocks` split must keep the
generated tests identical in name and body — compare `mix test` counts per suite
before/after.
