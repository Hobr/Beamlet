#!/usr/bin/env python3
"""Run the official backend with a deadline and stop only its owned processes."""
import contextlib
import os
import signal
import subprocess
import sys

# 保留 Python 标准库的 POSIX 会话/进程组管理，专门负责官方 backend 的截止与回收。
# 预算是最长等待秒数，端口用于本次专用服务；可选源/模块/深度用于明确范围的诊断。
budget, port = int(sys.argv[1]), int(sys.argv[2])
source = sys.argv[3] if len(sys.argv) > 3 else "spec/quint/core/composition.qnt"
main = sys.argv[4] if len(sys.argv) > 4 else "composition"
depth = sys.argv[5] if len(sys.argv) > 5 else "10"
command = ["quint", "verify", source, "--main", main, "--init", "init", "--step", "step",
           "--invariant", "safety", "--max-steps", depth, "--random-transitions=false", "--backend", "apalache",
           "--server-endpoint", f"localhost:{port}", "--verbosity", "2"]
print("Command:", " ".join(command), flush=True)
# 打印只供阅读，执行仍传独立 argv；新会话使 PID 同时成为独占进程组 ID，不波及无关进程。
# 清理只覆盖该组；自行另起会话/进程组的后代不在保证内。
process = subprocess.Popen(command, start_new_session=True)
try:
    code = process.wait(timeout=budget)
except subprocess.TimeoutExpired:
    # 124 标记预算耗尽、请求界限无结论；不能把正在检查的 State 当作已完成界限。
    print(f"INCONCLUSIVE: timeout after {budget}s; no completed depth-{depth} result", flush=True)
    code = 124
finally:
    # 成功、失败或超时都回收本组：先 SIGTERM，等待主进程至多 5 秒，再用 SIGKILL 收尾。
    # 即使主进程已退出，最后一次 killpg 仍清除同组遗留后代。
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
