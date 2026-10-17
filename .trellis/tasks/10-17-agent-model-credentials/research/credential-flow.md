# Credential Flow Inspection

Scope update: the observed source facts below remain valid. The key-only design
and migration proposals below are superseded by provider-abstraction.md and the
revised PRD/design after the user's provider-extensibility clarification.

Planning evidence at source commit18137b1, inspected2026-10-17. No product edits,
model requests, dependency changes or application tests were performed.

## Confirmed Integration Points

- Actions ordinary bounded-data policy rejects credential labels recursively:
  apps/beamlet_actions/lib/beamlet/actions.ex:3. Operation.validate currently checks
  the whole ordinary map and full serialized size:
  apps/beamlet_actions/lib/beamlet/actions/operation.ex:36. Adding a dedicated
  validated Operation.credentials field avoids weakening payload/result policy.
- Runtime public submit and executor admission both validate the Operation.
  ExecutorGateway starts Worker by MFA at executor_gateway.ex:232; Worker builds
  the local handler context at worker.ex:15. These are the forwarding points;
  node discovery and resource selection need no credential interpretation.
- Agent server validates the option allowlist at server.ex:85, stores state in
  init, dispatches model work at server.ex:382 and all operations at server.ex:609.
  Tool dispatch is server.ex:726. The snapshot projection at server.ex:769 excludes
  internal options/state. Explicit delegation options use the same validator.
- Caller currently emits only profile/request in the portable payload. Handler
  resolves executor settings and calls native complete/invoke. Bind the Agent key
  outside messages and ordinary payload, then consume only at model execution.
- OpenAICompatible currently uses settings.key_env/System.get_env at line23,
  accepts keys only via that environment path and places them in Req auth, not
  the JSON body. Keep its no-retry/TLS/size normalization contracts.
- Node.Provider at provider.ex:20 couples readiness to a local key_env. Reuse the
  adapter's noncredential configuration validation after separating authentication.
- Current direct Harness HTTP tests, Node release integration and deployment
  README/node.example.exs contain key_env setup and must migrate together.
  Archived acceptance reports are historical evidence and must stay intact.

## Approved Intent and Proposed Migration

User intent: plaintext key at Agent creation, stored by authority, transmitted
with each model call and temporarily usable by an eligible executor. No extra
credential management/security product is requested.

The design proposes explicit direct Harness api_key and rejection of key_env,
rather than maintaining an executor-environment fallback. Final planning approval
must include this migration. Existing specs describe the prior baseline; the
approved task PRD/design override only those credential-sourcing statements.
All unrelated limits, dependency directions, public admission, actual-DOWN
lifecycle gates, uncertainty and no-retry behavior remain applicable.

## Evidence Limits

Inspection establishes call sites and existing contracts, not passing evidence
for the new feature. Tests will use synthetic keys and a real local HTTP fixture
on independent same-host VMs. No physical execution or paid/live model request
is needed. Ordinary projections do not promise protection from malicious model
echo, arbitrary handler code or administrators inspecting process memory.
