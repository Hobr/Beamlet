#!/usr/bin/env python3
"""Run the official backend with a deadline and stop only its owned processes."""
import contextlib
import os
import signal
import subprocess
import sys

budget, port = int(sys.argv[1]), int(sys.argv[2])
source = sys.argv[3] if len(sys.argv) > 3 else "spec/quint/core/composition.qnt"
main = sys.argv[4] if len(sys.argv) > 4 else "composition"
depth = sys.argv[5] if len(sys.argv) > 5 else "10"
command = ["quint", "verify", source, "--main", main, "--init", "init", "--step", "step",
           "--invariant", "safety", "--max-steps", depth, "--random-transitions=false", "--backend", "apalache",
           "--server-endpoint", f"localhost:{port}", "--verbosity", "2"]
print("Command:", " ".join(command), flush=True)
process = subprocess.Popen(command, start_new_session=True)
try:
    code = process.wait(timeout=budget)
except subprocess.TimeoutExpired:
    print(f"INCONCLUSIVE: timeout after {budget}s; no completed depth-{depth} result", flush=True)
    code = 124
finally:
    with contextlib.suppress(ProcessLookupError):
        os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    with contextlib.suppress(ProcessLookupError):
        os.killpg(process.pid, signal.SIGKILL)
sys.exit(code)
