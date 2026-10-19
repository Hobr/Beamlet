# Function coverage inventory

The initial AST baseline at `7ccec067` was1346 functions, including559 public,772 private,13 delegates and2 macros across148 files and13 apps; none had an explicit source spec. Clauses/default wrappers were not counted as independent source functions.

The final complete coverage is **1345/1345, zero missing and zero scanner errors**. The difference is the proved unreachable Agent `helper_monitors/1` removal: private functions decrease to771; all other identity categories are unchanged. No ordinary function is exempted.

The generated full inventory was removed during user-requested cleanup. Regenerate identities, locations, clauses, default heads, contracts and framework-generation boundaries with:

```sh
elixir scripts/quality/check-contracts.exs --inventory
```

The default scan covers every `apps/*/lib/**/*.ex`. No source is evaluated and no whole-application/module exemption mechanism exists. Missing contracts, parse errors and unclassified definitions exit1; invalid CLI options exit2. Forty permanent checker fixtures exercise public/private negatives, defaults, nested modules, delegates, macros, quote templates and framework boundaries.

## Ownership and ordering

- Actions owns generic Operation/Execution/Result/Handler types; Harness independently owns native Model/Tool/Context/catalogue types.
- Foundation owns neutral Repo/dataset/installation/codec/transaction/artifact types and never references a domain.
- Actions Storage references Actions/Foundation; Agent Storage references the lower storage owners, never Agent/Core/Runtime.
- Runtime consumes lower Actions/storage contracts; Core consumes Harness while retaining pure reduction/context types.
- Agent composes these lower contracts. Node composes Agent/Runtime/storage roles; Server, CLI and Web are hosts, with no reverse dependency from libraries.
- I18n is a presentational leaf. Types were added along existing dependencies; no child manifest changed.

Final tests, semantic review, PLT evidence and LSP limitations are summarized in [final-verification.md](final-verification.md). Per-warning reasoning and dead-code proofs are in [return-dispositions.md](return-dispositions.md).
