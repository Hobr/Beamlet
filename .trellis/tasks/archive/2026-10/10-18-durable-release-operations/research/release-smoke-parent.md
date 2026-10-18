# Parent-run release smoke (stage F)

Environment: nix OTP 29 / Elixir 1.20, release built with `BEAMLET_BACKEND_BUILD=1`, isolated
node names, cookies and distribution ports. Note: `$REL rpc ...` is unusable in this
environment (it exits 0 and prints nothing), so probes use a separate
`erl -name <probe>@127.0.0.1 -setcookie ... -eval 'rpc:call(...)'`.

Also note: `$REL start` runs the release in the **foreground**. Any smoke script must
background it and poll for readiness; an unbounded `start` in a pipeline blocks forever.

## Daemon release with storage configured

```sh
BEAMLET_CONFIG=/tmp/beamlet-rel/daemon.exs BEAMLET_DIST_PORT=9416 \
RELEASE_NODE=beamlet_stagef_p2@127.0.0.1 RELEASE_COOKIE=*** \
  _build/backend/prod/rel/beamlet_daemon/bin/beamlet_daemon start &
```

epmd reported the node, and the probe returned:

```elixir
#{datasets => #{authority => ready, journal => ready},
  boot_id => <<"e7880292-26ff-40d8-8f8e-c2a4ae1e1bb5">>, admission => admitted}
```

`rpc:call(node, erlang, whereis, ['Elixir.Beamlet.Storage.Admission'])` returned a live pid,
so the durable admission process ships in the packaged release and both datasets open ready.
The node shut down cleanly via `rpc:call(node, init, stop, [])`.

## CLI release without a database

```sh
RELEASE_NODE=beamlet_cli_sf@127.0.0.1 RELEASE_COOKIE=*** BEAMLET_DIST_PORT=9418 \
BEAMLET_CONFIG=/tmp/cli-nodb.exs \
  _build/backend/prod/rel/beamlet_cli/bin/beamlet_cli start   # empty stdin
```

Exit 0 with no database configured: the interaction-only host does not require storage.

## What this proves and does not prove

Proves: the packaged daemon boots with durable storage configured, both datasets open ready,
admission is admitted, the admission process is alive, and the CLI release runs without a
database.

Does not prove: physical power-loss durability, cross-host deployment, PostgreSQL inside the
release, a long soak, or that a restored backup is handled correctly on a real operator
dataset (that path is covered by unit-level refusal tests only).
