#!/usr/bin/env python3
"""One copied daemon, three named boots, bounded controls and a remote model turn."""
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


class Service:
    def __init__(self, root, logs, label, settings, cookie, port=None):
        self.root = root
        self.logs = logs
        self.label = label
        self.executable = str(root / "release/bin/beamlet_daemon")
        self.env = os.environ.copy()
        self.env.update(
            RELEASE_NODE=f"{label}_{os.getpid()}@127.0.0.1",
            RELEASE_COOKIE=cookie,
            BEAMLET_CONFIG=str(root / f"{label}.exs"),
        )
        for key in ["SECRET_KEY_BASE", "BEAMLET_MODEL_KEY", "BEAMLET_DIST_PORT"]:
            self.env.pop(key, None)
        if port is not None:
            self.env["BEAMLET_DIST_PORT"] = str(port)
        Path(self.env["BEAMLET_CONFIG"]).write_text("import Config\n" + settings + "\n")
        self.process = None
        self.log = None

    def command(self, *args, timeout=10):
        return subprocess.run(
            [self.executable, *args], env=self.env, cwd=self.root,
            capture_output=True, text=True, timeout=timeout,
        )

    def rpc(self, expression):
        result = self.command("rpc", expression)
        (self.logs / f"{self.label}-rpc.log").open("a").write(result.stdout + result.stderr)
        assert result.returncode == 0, f"{self.label}: RPC failed (see evidence log)"
        return result.stdout

    def start(self):
        self.log = (self.logs / f"{self.label}-boot.log").open("w")
        self.process = subprocess.Popen(
            [self.executable, "start"], env=self.env, cwd=self.root,
            stdout=self.log, stderr=self.log,
        )
        deadline = time.monotonic() + 20
        while self.command("rpc", ":ok", timeout=5).returncode != 0:
            assert self.process.poll() is None and time.monotonic() < deadline, \
                f"{self.label}: readiness failed (see boot log)"
            time.sleep(0.1)

    def stop(self):
        failures = []
        try:
            if self.process is not None and self.process.poll() is None:
                result = self.command("stop")
                assert result.returncode == 0, f"{self.label}: stop failed"
                self.process.wait(timeout=10)
        except Exception as error:
            failures.append(error)
        try:
            if self.process is not None and self.process.poll() is None:
                self.process.kill()
                self.process.wait(timeout=5)
        except Exception as error:
            failures.append(error)
        try:
            if self.log is not None:
                self.log.close()
        except Exception as error:
            failures.append(error)
        report_cleanup_failures(failures)


def report_cleanup_failures(failures, primary=None):
    if not failures:
        return
    error = primary if primary is not None else failures[0]
    for failure in failures if primary is not None else failures[1:]:
        error.add_note(f"Additional cleanup failure: {type(failure).__name__}: {failure}")
        # str(exception) excludes notes already collected during service cleanup.
        for note in getattr(failure, "__notes__", ()):
            error.add_note(note)
    if primary is None:
        raise error


def stop_services(*services):
    # Called from finally: retain the active startup/RPC error as the primary one.
    primary = sys.exception()
    failures = []
    for service in services:
        try:
            service.stop()
        except Exception as error:
            failures.append(error)
    report_cleanup_failures(failures, primary)


def main():
    logs = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(tempfile.mkdtemp(prefix="beamlet-named-logs-"))
    logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="beamlet-named-") as work:
        root = Path(work)
        shutil.copytree(sys.argv[1], root / "release")
        cookie = secrets.token_hex(24)
        for role in ["default", "authority", "executor"]:
            node = "[]" if role == "default" else f"[roles: [:{role}]]"
            failed_peer = ', allowed_nodes: ["missing@127.0.0.1"], peers: ["missing@127.0.0.1"]' if role == "default" else ""
            service = Service(root, logs, role, f"config :beamlet_daemon, node: {node}{failed_peer}", cookie)
            try:
                service.start()
                service.rpc(f'''
                  true = Node.alive?()
                  true = Atom.to_string(node()) == System.fetch_env!("RELEASE_NODE")
                  {{:ok, 9100}} = :application.get_env(:kernel, :inet_dist_listen_min)
                  true = (Process.whereis(Beamlet.Agent.Registry) != nil) == {str(role != "executor").lower()}
                  true = (Process.whereis(Beamlet.Runtime.ExecutorGateway) != nil) == {str(role != "authority").lower()}
                  true = (Process.whereis(Beamlet.Node.Provider) != nil) == {str(role != "authority").lower()}
                  false = Code.ensure_loaded?(Phoenix)
                  false = Code.ensure_loaded?(Beamlet.CLI.Client)
                ''')
                assert service.command("pid").returncode == 0
                if role == "default":
                    service.rpc('''
                      wait = fn wait, n ->
                        if Enum.any?(Supervisor.which_children(Beamlet.Daemon.Supervisor), fn {id, _, _, _} -> id == Beamlet.Daemon.Bootstrap end) do
                          true = n > 0
                          Process.sleep(20)
                          wait.(wait, n - 1)
                        end
                      end
                      wait.(wait, 300)
                      true = Process.alive?(Process.whereis(Beamlet.Agent.Registry))
                    ''')
                print(f"same copied daemon: named {role}, default port9100, RPC/pid/stop passed")
            finally:
                service.stop()
            if role == "default":
                assert "daemon startup peer 1: unavailable" in (logs / "default-boot.log").read_text()

        # Same copy simultaneously hosts two only configurations. Authority's
        # one-shot bootstrap connects executor; placement forbids local fallback.
        executor = Service(root, logs, "remote_executor", "config :beamlet_daemon, node: [roles: [:executor], limits: [refresh_ms: 20]]", cookie, 19102)
        executor_name = executor.env["RELEASE_NODE"]
        authority = Service(root, logs, "remote_authority", f'config :beamlet_daemon, node: [roles: [:authority], limits: [refresh_ms: 20]], allowed_nodes: ["{executor_name}"], peers: ["{executor_name}"]', cookie, 19101)
        try:
            executor.start()
            authority.start()
            authority.rpc(f'''
              executor = :"{executor_name}"
              wait = fn wait, n ->
                ready = Enum.any?(Beamlet.Runtime.Directory.snapshots(), fn {{_, r}} -> r.node == executor and r.execution_ready and "model.provider:deterministic" in r.capabilities end)
                unless ready do
                  true = n > 0
                  Process.sleep(20)
                  wait.(wait, n - 1)
                end
              end
              wait.(wait, 300)
              nil = Process.whereis(Beamlet.Runtime.ExecutorGateway)
              {{:ok, ref}} = Beamlet.Agent.start(node(), id: "copied-remote",
                model: %{{provider: "deterministic", config: %{{"reply" => %{{"kind" => "text", "content" => "remote-ok", "calls" => []}}}}, placement: %{{allowed_nodes: [executor]}}}})
              :ok = Beamlet.Agent.subscribe(ref)
              receive do
                {{:beamlet_agent, ^ref, seq, {{:snapshot, %{{status: :idle}}}}}} -> :ok = Beamlet.Agent.ack(ref, seq)
              after 1000 -> raise "initial snapshot timeout"
              end
              {{:ok, _}} = Beamlet.Agent.input(ref, "hello")
              done = fn done ->
                receive do
                  {{:beamlet_agent, ^ref, seq, {{:snapshot, snapshot}}}} ->
                    :ok = Beamlet.Agent.ack(ref, seq)
                    case snapshot.status do
                      :done -> "remote-ok" = snapshot.final
                      :running -> done.(done)
                      _ -> raise "unexpected terminal status"
                    end
                after 5000 -> raise "remote turn timeout"
                end
              end
              done.(done)
              :ok = Beamlet.Agent.unsubscribe(ref)
              :ok = Beamlet.Agent.close(ref)
              IO.puts("copied authority to executor deterministic turn passed")
            ''')
            print("copied authority bootstrap to executor and one deterministic Gateway turn passed")
        finally:
            stop_services(authority, executor)

        # Reader/host errors must be static and never include raw config or causes.
        sentinel = "PRIVATE_CONFIG_SENTINEL"
        probe = Service(root, logs, "invalid", "config :beamlet_daemon, node: []", cookie)
        cases = {
            "authority-limits": f'config :beamlet_daemon, node: [roles: [:authority], limits: "{sentinel}"]',
            "interaction": 'config :beamlet_daemon, node: [roles: [:interaction]]',
            "empty": "config :beamlet_daemon, node: [roles: []]",
            "duplicate": "config :beamlet_daemon, node: [roles: [:authority, :authority]]",
            "unknown-role": "config :beamlet_daemon, node: [roles: [:unknown]]",
            "wrong-app": f'config :beamlet_node, :retired, "{sentinel}"',
            "reader-exception": f'raise "{sentinel}"',
            "syntax": f'config :beamlet_daemon, bad: "{sentinel}" ]',
            "bad-provider": f'config :beamlet_daemon, node: [model_providers: %{{"{sentinel}" => String}}]',
            "untrusted-peer": 'config :beamlet_daemon, peers: ["missing@127.0.0.1"]',
        }
        for label, content in cases.items():
            Path(probe.env["BEAMLET_CONFIG"]).write_text("import Config\n" + content + "\n")
            result = probe.command("start")
            output = result.stdout + result.stderr
            (logs / f"reject-{label}.log").write_text(output)
            assert result.returncode != 0
            assert "invalid daemon configuration" in output
            if label == "authority-limits":
                # Config providers run before application/role supervision starts.
                assert "Config provider Config.Reader failed" in output
            assert sentinel not in output
            assert "invalid runtime limit" not in output
            assert "failed to start child" not in output
        for label, path in [("relative", "relative.exs"), ("missing", str(root / "absent.exs"))]:
            probe.env["BEAMLET_CONFIG"] = path
            result = probe.command("start")
            (logs / f"reject-{label}.log").write_text(result.stdout + result.stderr)
            assert result.returncode != 0
            assert "invalid daemon configuration" in result.stdout + result.stderr
        print("12 invalid runtime/config cases rejected without raw sentinel leakage")


if __name__ == "__main__":
    main()
