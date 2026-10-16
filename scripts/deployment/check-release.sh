#!/usr/bin/env bash
set -euo pipefail
# Run from checkout root; everything booted below is copied outside the checkout.
script_dir=$(cd "$(dirname "$0")" && pwd)
release=${1:-_build/backend/prod/rel/beamlet_node}
work=$(mktemp -d /tmp/beamlet-release.XXXXXX)
trap 'rm -rf "$work"' EXIT
cp -a "$release" "$work/release"
if find "$work/release/lib" -maxdepth 1 -type d | grep -Ei '/(beamlet_web|phoenix[^/]*|bandit|plug[^/]*|websock[^/]*)-'; then
  echo 'Forbidden Web artifact shipped' >&2
  exit 1
fi
cat "$work/release/releases/0.1.0/beamlet_node.rel"
find "$work/release/lib" -name '*.app' -print | sort
export RELEASE_NODE="acceptance_$$@127.0.0.1" RELEASE_DISTRIBUTION=name
export RELEASE_COOKIE
RELEASE_COOKIE=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
export BEAMLET_CONFIG="$work/node.exs" BEAMLET_DIST_PORT=19100
unset SECRET_KEY_BASE BEAMLET_MODEL_KEY
cd "$work"
for role in authority executor; do
  printf 'import Config\nconfig :beamlet_node, :boot, roles: [:%s]\n' "$role" >"$BEAMLET_CONFIG"
  BEAMLET_EXPECT_ROLE="$role" ./release/bin/beamlet_node eval '
    forbidden? = fn app ->
      Regex.match?(~r/\A(beamlet_web|phoenix.*|plug.*|bandit|websock.*)\z/, Atom.to_string(app))
    end
    release_root = System.fetch_env!("RELEASE_ROOT")
    {:ok, [{:release, _, _, apps}]} =
      :file.consult(String.to_charlist(Path.join(release_root, "releases/0.1.0/beamlet_node.rel")))
    false = Enum.any?(apps, fn app -> forbidden?.(elem(app, 0)) end)
    for file <- Path.wildcard(Path.join(release_root, "lib/*/ebin/*.app")) do
      {:ok, [{:application, app, properties}]} = :file.consult(String.to_charlist(file))
      false = forbidden?.(app)
      required = Keyword.get(properties, :applications, []) -- Keyword.get(properties, :optional_applications, [])
      false = Enum.any?(required, forbidden?)
    end
    {:ok, _} = Application.ensure_all_started(:beamlet_node)
    authority? = System.fetch_env!("BEAMLET_EXPECT_ROLE") == "authority"
    true = (Process.whereis(Beamlet.Agent.Registry) != nil) == authority?
    true = (Process.whereis(Beamlet.Runtime.ExecutorGateway) != nil) == not authority?
    false = Code.ensure_loaded?(Phoenix)
    false = Code.ensure_loaded?(Beamlet.Web.Endpoint)
    IO.puts("copied release role boot passed")
  '
done

python3 "$script_dir/check-named-release.py" "$work/release"
