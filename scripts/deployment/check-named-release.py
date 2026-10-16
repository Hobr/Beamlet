#!/usr/bin/env python3
"""Verify copied named release startup, RPC and stop with finite process bounds."""
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def main():
    with tempfile.TemporaryDirectory(prefix="beamlet-named-") as work:
        root = Path(work)
        shutil.copytree(sys.argv[1], root / "release")
        executable = str(root / "release/bin/beamlet_node")
        env = os.environ.copy()
        env.update(
            RELEASE_NODE=f"acceptance_{os.getpid()}@127.0.0.1",
            RELEASE_COOKIE=secrets.token_hex(24),
            BEAMLET_CONFIG=str(root / "node.exs"),
            BEAMLET_DIST_PORT="19101",
        )
        for key in ["SECRET_KEY_BASE", "BEAMLET_MODEL_KEY"]:
            env.pop(key, None)

        def command(*args, timeout=10):
            return subprocess.run(
                [executable, *args], env=env, cwd=root, capture_output=True,
                text=True, timeout=timeout,
            )

        for role in ["authority", "executor"]:
            (root / "node.exs").write_text(
                f"import Config\nconfig :beamlet_node, :boot, roles: [:{role}]\n"
            )
            with (root / "boot.log").open("w") as log:
                process = subprocess.Popen(
                    [executable, "start"], env=env, cwd=root, stdout=log, stderr=log,
                )
                try:
                    deadline = time.monotonic() + 20
                    while command("rpc", ":ok", timeout=5).returncode != 0:
                        if process.poll() is not None or time.monotonic() >= deadline:
                            raise RuntimeError("named release readiness failed")
                    expression = f'''
                      true = Node.alive?()
                      true = Atom.to_string(node()) == System.fetch_env!("RELEASE_NODE")
                      {{:ok, 19101}} = :application.get_env(:kernel, :inet_dist_listen_min)
                      true = (Process.whereis(Beamlet.Agent.Registry) != nil) == {str(role == "authority").lower()}
                      true = (Process.whereis(Beamlet.Runtime.ExecutorGateway) != nil) == {str(role == "executor").lower()}
                      false = Code.ensure_loaded?(Phoenix)
                      IO.puts("named copied {role} boot passed")
                    '''
                    result = command("rpc", expression)
                    if result.returncode != 0:
                        raise RuntimeError("named release role assertions failed")
                    print(result.stdout.strip())
                    if command("stop").returncode != 0:
                        raise RuntimeError("named release stop failed")
                    process.wait(timeout=10)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait(timeout=5)
        env["BEAMLET_CONFIG"] = "relative.exs"
        result = command("eval", ":ok")
        assert result.returncode != 0
        assert "BEAMLET_CONFIG must be an absolute" in result.stderr
        print("relative trusted config rejected")


if __name__ == "__main__":
    main()
