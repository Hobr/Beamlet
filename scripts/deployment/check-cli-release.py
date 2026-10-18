#!/usr/bin/env python3
"""Copied foreground CLI sessions retain one live Agent across quit and EOF."""
import base64
import hashlib
import importlib.util
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("named", Path(__file__).with_name("check-named-release.py"))
assert spec is not None and spec.loader is not None
pty_spec = importlib.util.spec_from_file_location("cli_pty", Path(__file__).with_name("test-cli-pty.py"))
assert pty_spec is not None and pty_spec.loader is not None
cli_pty = importlib.util.module_from_spec(pty_spec)
pty_spec.loader.exec_module(cli_pty)

named = importlib.util.module_from_spec(spec)
spec.loader.exec_module(named)


def main():
    logs = Path(sys.argv[3]).resolve()
    logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="beamlet-cli-copy-") as tmp:
        root = Path(tmp)
        shutil.copytree(sys.argv[1], root / "release")
        shutil.copytree(sys.argv[2], root / "cli")
        manifest = "".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root / 'cli')}\n" for p in sorted((root / "cli").rglob("*")) if p.is_file())
        (logs / "copied-cli-manifest.sha256").write_text(manifest)
        (logs / "copied-cli-tree.sha256").write_text(hashlib.sha256(manifest.encode()).hexdigest() + "\n")
        forbidden = re.compile(r"^(beamlet_daemon|beamlet_web|beamlet_config|beamlet_app_server|beamlet_app_web|phoenix.*|plug.*|bandit|websock.*)-")
        assert not any(forbidden.match(p.name) for p in (root / "cli/lib").iterdir())
        cookie = secrets.token_hex(24)
        daemon = named.Service(root, logs, "cli_authority", 'config :beamlet_app_server, node: [limits: [refresh_ms: 20]]', cookie)
        authority = daemon.env["RELEASE_NODE"]
        runtime = root / "cli/releases/0.1.0/runtime.exs"
        runtime.write_text(runtime.read_text() + f'\nconfig :beamlet_cli, allowed_nodes: ["{authority}"]\n')
        options = root / "options.exs"
        options.write_text('import Config\nconfig :beamlet_cli, agent_options: [id: "persist", model: %{provider: "deterministic", config: %{"reply" => %{"kind" => "text", "content" => "copied-ok", "calls" => []}}}]\n')

        def session(label, commands):
            env = daemon.env.copy()
            env.update(RELEASE_NODE=f"{label}_{secrets.token_hex(6)}@127.0.0.1", BEAMLET_LANG="en")
            result = subprocess.run([str(root / "cli/bin/beamlet_cli"), "start"], input=commands, text=True, capture_output=True, cwd=root, env=env, timeout=25)
            output = result.stdout + result.stderr
            (logs / f"{label}.log").write_text(output)
            assert result.returncode == 0, f"{label}: CLI failed"
            assert "error:" not in output, f"{label}: command failed"
            return output

        try:
            daemon.start()
            width_env = daemon.env.copy()
            width_env.update(RELEASE_NODE=f"width_{secrets.token_hex(6)}@127.0.0.1", BEAMLET_LANG="en")
            width = subprocess.run([str(root / "cli/bin/beamlet_cli"), "eval",
                'true = Code.ensure_loaded?(Ucwidth); 4 = Owl.Data.length("中国"); 2 = Owl.Data.length("😀"); 1 = Owl.Data.length("é"); IO.puts("Ucwidth enabled")'],
                cwd=root, env=width_env, capture_output=True, timeout=25)
            (logs / 'copied-width.log').write_bytes(width.stdout + width.stderr)
            assert width.returncode == 0 and b'Ucwidth enabled' in width.stdout
            assert any(p.name.startswith('ucwidth-') for p in (root / 'cli/lib').iterdir())
            invalid = subprocess.run([str(root / 'cli/bin/beamlet_cli'), 'start'], input=b'\xff\n',
                cwd=root, env=width_env, capture_output=True, timeout=25)
            (logs / 'invalid-pipe.log').write_bytes(invalid.stdout + invalid.stderr)
            assert invalid.returncode == 1 and b'error: invalid_command' in invalid.stdout, 'native invalid input must fail honestly'

            first = session("session_a", f"connect {authority}\ncreate {authority} {options}\nquit\n")
            assert "id64:cGVyc2lzdA" in first
            identity = daemon.rpc('{:ok, ref} = Beamlet.Agent.lookup(node(), "persist"); IO.puts(inspect(ref, limit: :infinity))')
            second = session("session_b", f"connect {authority}\nagents {authority}\nattach {authority} persist a\nstatus a\ninput a hello\nwatch a 5000 64\nstop a\ndetach a\n")
            assert "copied-ok" in second and "id64:cGVyc2lzdA" in second
            unchanged = daemon.rpc('{:ok, ref} = Beamlet.Agent.lookup(node(), "persist"); IO.puts(inspect(ref, limit: :infinity))')
            assert identity == unchanged, "authority/PID/incarnation changed across quit/EOF"
            third = session("session_c", f"connect {authority}\nattach {authority} persist a\nclose a\nquit\n")
            assert "id64:cGVyc2lzdA" in third
            daemon.rpc('{:error, :not_found} = Beamlet.Agent.lookup(node(), "persist")')
            ids = [f"unique-{n:02}" for n in range(10)] + ['café 中国 é😀', 'two words"\\\n\t\x1b']
            for agent_id in ids:
                encoded = base64.b64encode(agent_id.encode()).decode()
                daemon.rpc(f'{{:ok, _}} = Beamlet.Agent.start(node(), id: Base.decode64!("{encoded}"), model: %{{provider: "deterministic", config: %{{"reply" => %{{"kind" => "text", "content" => "pty-ok", "calls" => []}}}}}})')
            listing = session("enumeration", f"connect {authority}\nagents {authority}\nagents-page 2\nquit\n")
            for agent_id in ids:
                token = "id64:" + base64.urlsafe_b64encode(agent_id.encode()).decode().rstrip('=')
                assert token in listing, f"missing identity {token}"
            assert 'page=2/2' in listing
            commands = f"connect {authority}\n"
            for index, agent_id in enumerate(ids[-2:]):
                token = "id64:" + base64.urlsafe_b64encode(agent_id.encode()).decode().rstrip('=')
                commands += f"attach {authority} {token} p{index}\nstatus p{index}\ninput p{index} café 中国 é😀  spaces  \nwatch p{index} 5000 64\n"
            commands += "quit\n"
            env = daemon.env.copy()
            env.update(RELEASE_NODE=f"pty_{secrets.token_hex(6)}@127.0.0.1", BEAMLET_LANG="en")
            status, output = cli_pty.terminal([str(root / 'cli/bin/beamlet_cli'), 'start'], commands.encode(), cwd=root, env=env)
            (logs / 'copied-pty.log').write_bytes(output)
            # pty-ok is emitted by the model, never present in input/terminal echo.
            assert status == 0 and b'error:' not in output and output.count(b'pty-ok') >= 2, output
            print("Copied CLI closure and three independent foreground stdin sessions passed; same Ref after quit and EOF, explicit close verified")
        finally:
            named.stop_services(daemon)


if __name__ == "__main__":
    main()
