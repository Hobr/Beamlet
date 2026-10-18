#!/usr/bin/env bash
set -euo pipefail
# One copied artifact, three startup configurations; library tests own seven roles.
script_dir=$(cd "$(dirname "$0")" && pwd)
release=$(realpath "${1:-_build/backend/prod/rel/beamlet_daemon}")
cli_release=$(realpath "${2:-_build/backend/prod/rel/beamlet_cli}")
web_release=$(realpath "${3:-_build/prod/rel/beamlet_web}")
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
if find "$work/release/lib" -maxdepth 1 -type d | grep -Ei '/(beamlet_config|beamlet_cli|beamlet_web|beamlet_i18n|gettext|expo|phoenix[^/]*|bandit|plug[^/]*|websock[^/]*)-'; then
  echo 'Forbidden host/Web artifact shipped' >&2
  exit 1
fi
cat "$work/release/releases/0.1.0/beamlet_daemon.rel" >"$logs/release.rel"
find "$work/release/lib" -name '*.app' -print | sort >"$logs/app-paths.log"
export RELEASE_NODE="closure_$$@127.0.0.1" RELEASE_DISTRIBUTION=name
export RELEASE_COOKIE
RELEASE_COOKIE=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
unset SECRET_KEY_BASE BEAMLET_MODEL_KEY BEAMLET_CONFIG BEAMLET_DIST_PORT
# Native usage/version are available without former mandatory shell settings.
for name in beamlet_daemon beamlet_cli beamlet_web; do
  case "$name" in
  beamlet_daemon) artifact="$work/release" ;;
  beamlet_cli) artifact="$cli_release" ;;
  beamlet_web) artifact="$web_release" ;;
  esac
  env -u RELEASE_NODE -u RELEASE_COOKIE -u RELEASE_DISTRIBUTION \
    "$artifact/bin/$name" >"$logs/$name-help.log" 2>&1
  env -u RELEASE_NODE -u RELEASE_COOKIE -u RELEASE_DISTRIBUTION \
    "$artifact/bin/$name" version >"$logs/$name-version.log" 2>&1
  test ! -e "$artifact/bin/beamlet"
  ! grep -q 'BEAMLET_' "$artifact/releases/0.1.0/env.sh"
done
cd "$work"
./release/bin/beamlet_daemon eval '
  forbidden? = fn app ->
    Regex.match?(~r/\A(beamlet_config|beamlet_cli|beamlet_web|beamlet_i18n|gettext|expo|phoenix.*|plug.*|bandit|websock.*)\z/, Atom.to_string(app))
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

# Web also uses its bundled runtime.exs, with no backend host in its closure.
cp -a "$web_release" "$work/web"
(
  cd "$work/web"
  find . -type f -print0 | sort -z | xargs -0 sha256sum
) >"$logs/web-manifest.sha256"
sha256sum "$logs/web-manifest.sha256" >"$logs/web-tree.sha256"
python3 - "$work/web" "$logs" "$script_dir" <<'PY'
import os
import re
import runpy
import secrets
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

root, logs, scripts = map(Path, sys.argv[1:])
report_cleanup_failures = runpy.run_path(str(scripts / "check-named-release.py"))["report_cleanup_failures"]
assert not any(re.match(r"beamlet_(daemon|cli|config)-", p.name) for p in (root / "lib").iterdir())
launcher = str(root / "bin/beamlet_web")
env = os.environ.copy()
for key in ["BEAMLET_CONFIG", "BEAMLET_DIST_PORT", "RELEASE_NODE", "RELEASE_COOKIE", "RELEASE_DISTRIBUTION", "SECRET_KEY_BASE"]:
    env.pop(key, None)
missing = subprocess.run([launcher, "start"], cwd=root, env=env, capture_output=True, timeout=20)
(logs / "web-missing-secret.log").write_bytes(missing.stdout + missing.stderr)
assert missing.returncode != 0 and b"SECRET_KEY_BASE is missing" in missing.stdout + missing.stderr
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
# Test-only listener fixture in the copied artifact; no new deployment variable.
runtime = root / "releases/0.1.0/runtime.exs"
runtime.write_text(runtime.read_text() + f'\nconfig :beamlet_web, Beamlet.Web.Endpoint, http: [ip: {{127, 0, 0, 1}}, port: {port}]\n')
env["SECRET_KEY_BASE"] = secrets.token_urlsafe(64)
process = None
with (logs / "web-boot.log").open("wb") as log:
    try:
        process = subprocess.Popen([launcher, "start"], cwd=root, env=env, stdout=log, stderr=log)
        deadline = time.monotonic() + 25
        while True:
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=2) as response:
                    assert response.status == 200
                    html = response.read().decode()
                break
            except OSError:
                assert process.poll() is None and time.monotonic() < deadline, "Web HTTP readiness failed"
                time.sleep(0.1)
        (logs / "web-home.html").write_text(html)
        assets = set(re.findall(r'(?:src|href)="(/assets/[^"?]+)', html))
        assert any(".js" in path for path in assets) and any(".css" in path for path in assets), assets
        for index, path in enumerate(sorted(assets)):
            with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=5) as response:
                body = response.read()
                assert response.status == 200 and body
                (logs / f"web-static-{index}.log").write_text(f"{path}: HTTP 200, {len(body)} bytes, {response.headers['Content-Type']}\n")
        rpc = subprocess.run([launcher, "rpc", 'true = Process.whereis(Beamlet.Node) != nil; false = Code.ensure_loaded?(Beamlet.Daemon); false = Code.ensure_loaded?(Beamlet.CLI); IO.puts("Web host isolation passed")'], cwd=root, env=env, capture_output=True, timeout=10)
        (logs / "web-rpc.log").write_bytes(rpc.stdout + rpc.stderr)
        assert rpc.returncode == 0
        assert subprocess.run([launcher, "pid"], cwd=root, env=env, capture_output=True, timeout=10).returncode == 0
    finally:
        primary = sys.exception()
        failures = []
        if process is not None and process.poll() is None:
            try:
                stop = subprocess.run([launcher, "stop"], cwd=root, env=env, capture_output=True, timeout=10)
                assert stop.returncode == 0, "Web stop failed"
                process.wait(timeout=10)
            except Exception as error:
                failures.append(error)
            try:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=5)
            except Exception as error:
                failures.append(error)
        report_cleanup_failures(failures, primary)
print("Copied Web: secret rejection, native defaults/controls, HTTP and CSS/JS serving passed")
PY
