#!/usr/bin/env python3
"""One copied daemon, three named boots, bounded controls and a remote model turn."""
import contextlib
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


class Service:
    def __init__(self, root, logs, label, settings, cookie):
        self.root = root
        self.logs = logs
        self.label = label
        # Each fixture edits its own bundled runtime.exs, never a custom external
        # configuration interface. Controls remain the native Mix launcher.
        release = root / label
        shutil.copytree(root / "release", release)
        self.executable = str(release / "bin/beamlet_server")
        runtime = release / "releases/0.1.0/runtime.exs"
        runtime.write_text(runtime.read_text() + "\n" + settings + "\n")
        self.env = os.environ.copy()
        self.env.update(
            RELEASE_NODE=f"{label}_{os.getpid()}@127.0.0.1",
            RELEASE_COOKIE=cookie,
            RELEASE_DISTRIBUTION="name",
        )
        for key in ["SECRET_KEY_BASE", "BEAMLET_MODEL_KEY", "BEAMLET_CONFIG", "BEAMLET_DIST_PORT"]:
            self.env.pop(key, None)
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


def daemon_smoke(root, logs, cookie):
    """Exercise native Unix background launch and observe the actual VM exit."""
    service = Service(root, logs, "background", "", cookie)
    pid = None
    try:
        result = service.command("daemon")
        (logs / "daemon-launch.log").write_text(result.stdout + result.stderr)
        assert result.returncode == 0, "native daemon launch failed"
        deadline = time.monotonic() + 20
        while True:
            result = service.command("rpc", "IO.puts(System.pid())", timeout=5)
            if result.returncode == 0:
                pid = int(result.stdout.strip())
                break
            assert time.monotonic() < deadline, "native daemon readiness failed"
            time.sleep(0.1)
        result = service.command("pid")
        assert result.returncode == 0 and int(result.stdout.strip()) == pid
        service.rpc("true = Process.whereis(Beamlet.Server.Supervisor) != nil")
        assert service.command("stop").returncode == 0
        deadline = time.monotonic() + 10
        while vm_running(pid):
            assert time.monotonic() < deadline, "native daemon did not exit"
            time.sleep(0.1)
        print("copied Server: native daemon launch/RPC/pid/stop and actual exit passed")
    finally:
        primary = sys.exception()
        failures = []
        try:
            result = service.command("pid")
            if result.returncode == 0:
                pid = int(result.stdout.strip())
            stopped = service.command("stop")
            if pid is not None and vm_running(pid):
                assert stopped.returncode == 0, "background cleanup stop failed"
                deadline = time.monotonic() + 10
                while vm_running(pid) and time.monotonic() < deadline:
                    time.sleep(0.1)
        except Exception as error:
            failures.append(error)
        # If control readiness failed, locate only this copied artifact's VM.
        # The private copy path is unique; never print process args/cookies.
        try:
            result = subprocess.run(
                ["ps", "-axo", "pid=,args="], capture_output=True, text=True,
                timeout=5, check=True,
            )
            release_root = str(Path(service.executable).parents[1])
            owned = {
                int(line.split(None, 1)[0]) for line in result.stdout.splitlines()
                if "beam.smp" in line and f"-root {release_root} " in line
            }
            if pid is not None:
                owned.add(pid)
            for owned_pid in owned:
                if vm_running(owned_pid):
                    with contextlib.suppress(ProcessLookupError):
                        os.kill(owned_pid, 9)
                    failures.append(AssertionError("background cleanup required killing VM"))
        except Exception as error:
            failures.append(error)
        report_cleanup_failures(failures, primary)


def vm_running(pid):
    # A reaped-by-init zombie is no longer a running VM (container PID 1 may lag).
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    stat = Path(f"/proc/{pid}/stat")
    if Path("/proc/self/stat").exists():
        try:
            return stat.read_text().rsplit(")", 1)[1].split()[0] != "Z"
        except FileNotFoundError:
            return False
    return True


def main():
    logs = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(tempfile.mkdtemp(prefix="beamlet-named-logs-"))
    logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="beamlet-named-") as work:
        root = Path(work)
        shutil.copytree(sys.argv[1], root / "release")
        cookie = secrets.token_hex(24)
        daemon_smoke(root, logs, cookie)
        for role in ["default", "authority", "executor"]:
            node = "[]" if role == "default" else f"[roles: [:{role}]]"
            failed_peer = ', allowed_nodes: ["missing@127.0.0.1"], peers: ["missing@127.0.0.1"]' if role == "default" else ""
            service = Service(root, logs, role, f"config :beamlet_app_server, node: {node}{failed_peer}", cookie)
            try:
                service.start()
                service.rpc(f'''
                  true = Node.alive?()
                  true = Atom.to_string(node()) == System.fetch_env!("RELEASE_NODE")
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
                        if Enum.any?(Supervisor.which_children(Beamlet.Server.Supervisor), fn {id, _, _, _} -> id == Beamlet.Server.Bootstrap end) do
                          true = n > 0
                          Process.sleep(20)
                          wait.(wait, n - 1)
                        end
                      end
                      wait.(wait, 300)
                      true = Process.alive?(Process.whereis(Beamlet.Agent.Registry))
                    ''')
                print(f"same copied daemon: named {role}, native distribution, RPC/pid/stop passed")
            finally:
                service.stop()
            if role == "default":
                assert "server startup peer 1: unavailable" in (logs / "default-boot.log").read_text()

        # Same copy simultaneously hosts two only configurations. Authority's
        # one-shot bootstrap connects executor; placement forbids local fallback.
        executor = Service(root, logs, "remote_executor", "config :beamlet_app_server, node: [roles: [:executor], limits: [refresh_ms: 20]]", cookie)
        executor_name = executor.env["RELEASE_NODE"]
        authority = Service(root, logs, "remote_authority", f'config :beamlet_app_server, node: [roles: [:authority], limits: [refresh_ms: 20]], allowed_nodes: ["{executor_name}"], peers: ["{executor_name}"]', cookie)
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

        # Application validators still reject malformed host options before roles
        # start. Native Config scripts are trusted code, not sanitized readers.
        sentinel = "PRIVATE_CONFIG_SENTINEL"
        cases = {
            "authority-limits": f'config :beamlet_app_server, node: [roles: [:authority], limits: "{sentinel}"]',
            "interaction": 'config :beamlet_app_server, node: [roles: [:interaction]]',
            "empty": "config :beamlet_app_server, node: [roles: []]",
            "duplicate": "config :beamlet_app_server, node: [roles: [:authority, :authority]]",
            "unknown-role": "config :beamlet_app_server, node: [roles: [:unknown]]",
            "unknown-key": f'config :beamlet_app_server, unknown: "{sentinel}"',
            "bad-provider": f'config :beamlet_app_server, node: [model_providers: %{{"{sentinel}" => String}}]',
            "untrusted-peer": 'config :beamlet_app_server, peers: ["missing@127.0.0.1"]',
            "invalid-storage": f'config :beamlet_app_server, storage: [adapter: :unknown, database: "{sentinel}"]',
        }
        for label, content in cases.items():
            probe = Service(root, logs, "invalid-" + label, content, cookie)
            result = probe.command("start")
            output = result.stdout + result.stderr
            (logs / f"reject-{label}.log").write_text(output)
            assert result.returncode != 0
            assert "invalid_server_configuration" in output
            assert sentinel not in output
            assert "invalid runtime limit" not in output
            assert "failed to start child" not in output
        # A configured but absent dataset must not be created/migrated by boot.
        database = root / "must-not-be-created.db"
        journal = root / "must-not-be-created-journal.db"
        probe = Service(root, logs, "missing-dataset", f'''config :beamlet_app_server,
          node: [roles: [:authority]],
          storage: [database: "{database}", dataset_id: "00000000-0000-4000-8000-000000000001",
            journal: [database: "{journal}", dataset_id: "00000000-0000-4000-8000-000000000002"],
            executor_id: "00000000-0000-4000-8000-000000000003"]''', cookie)
        try:
            probe.start()
            probe.rpc('''
              %{admission: {:refused, :dataset_missing},
                datasets: %{authority: {:refused, :dataset_missing}}} = Beamlet.Node.Storage.status()
              nil = Process.whereis(Beamlet.Agent.Storage.SQLiteAuthorityRepo)
              nil = Process.whereis(Beamlet.Actions.Storage.ExecutorJournalRepo)
            ''')
            assert not database.exists() and not journal.exists(), "boot created a database"
        finally:
            probe.stop()
        print("9 invalid host cases rejected without sentinel leakage; absent dataset not created")


if __name__ == "__main__":
    main()
