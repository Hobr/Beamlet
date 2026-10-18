#!/usr/bin/env bash
set -euo pipefail
# One copied artifact, three startup configurations; library tests own seven roles.
script_dir=$(cd "$(dirname "$0")" && pwd)
release=$(realpath "${1:-_build/backend/prod/rel/beamlet_daemon}")
cli_release=$(realpath "${2:-_build/backend/prod/rel/beamlet_cli}")
work=$(mktemp -d /tmp/beamlet-release.XXXXXX)
logs=${BEAMLET_CHECK_LOG_DIR:-$(mktemp -d /tmp/beamlet-release-logs.XXXXXX)}
mkdir -p "$logs"
trap 'rm -rf "$work"' EXIT
cp -a "$release" "$work/release"
printf 'Release evidence: %s\n' "$logs"
(
  cd "$work/release"
  find . -type f -print0 | sort -z | xargs -0 sha256sum
) >"$logs/copied-manifest.sha256"
sha256sum "$logs/copied-manifest.sha256" | tee "$logs/copied-tree.sha256"
# Presentation-only apps (and their Gettext/Expo dependencies) must stay out of the
# daemon closure too: `beamlet_i18n` is a leaf for Web and CLI copy, not core.
if find "$work/release/lib" -maxdepth 1 -type d | grep -Ei '/(beamlet_cli|beamlet_web|beamlet_i18n|gettext|expo|phoenix[^/]*|bandit|plug[^/]*|websock[^/]*)-'; then
  echo 'Forbidden host/Web artifact shipped' >&2
  exit 1
fi
cat "$work/release/releases/0.1.0/beamlet_daemon.rel" >"$logs/release.rel"
find "$work/release/lib" -name '*.app' -print | sort >"$logs/app-paths.log"
export RELEASE_NODE="closure_$$@127.0.0.1" RELEASE_DISTRIBUTION=name
export RELEASE_COOKIE
RELEASE_COOKIE=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
export BEAMLET_CONFIG="$work/daemon.exs"
unset SECRET_KEY_BASE BEAMLET_MODEL_KEY
printf 'import Config\nconfig :beamlet_daemon, node: []\n' >"$BEAMLET_CONFIG"
cd "$work"
./release/bin/beamlet_daemon eval '
  forbidden? = fn app ->
    Regex.match?(~r/\A(beamlet_cli|beamlet_web|beamlet_i18n|gettext|expo|phoenix.*|plug.*|bandit|websock.*)\z/, Atom.to_string(app))
  end
  root = System.fetch_env!("RELEASE_ROOT")
  {:ok, [{:release, _, _, apps}]} =
    :file.consult(String.to_charlist(Path.join(root, "releases/0.1.0/beamlet_daemon.rel")))
  false = Enum.any?(apps, fn app -> forbidden?.(elem(app, 0)) end)
  for file <- Path.wildcard(Path.join(root, "lib/*/ebin/*.app")) do
    {:ok, [{:application, app, properties}]} = :file.consult(String.to_charlist(file))
    false = forbidden?.(app)
    required = Keyword.get(properties, :applications, []) -- Keyword.get(properties, :optional_applications, [])
    false = Enum.any?(required, forbidden?)
  end
  [] = Application.spec(:beamlet_node, :mod)
  false = Code.ensure_loaded?(Phoenix)
  false = Code.ensure_loaded?(Beamlet.Web.Endpoint)
  false = Code.ensure_loaded?(Beamlet.CLI.Client)
  IO.puts("copied daemon closure passed")
'
python3 "$script_dir/check-named-release.py" "$work/release" "$logs"

python3 "$script_dir/check-cli-release.py" "$work/release" "$cli_release" "$logs/cli"
(
  cd "$cli_release"
  find . -type f -print0 | sort -z | xargs -0 sha256sum
) >"$logs/cli-manifest.sha256"
sha256sum "$logs/cli-manifest.sha256" >"$logs/cli-tree.sha256"
