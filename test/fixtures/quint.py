#!/usr/bin/env python3
"""Isolated orchestration fixture: never formal model/backend evidence."""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

# 此文件只冒充 CLI 输出/故障并记录 argv、cwd，供执行器回归；不运行 Quint 或证明模型性质。
args = sys.argv[1:]
with open(os.environ['QUINT_FIXTURE_RECORD'], 'a') as record:
    record.write(json.dumps({'argv': args, 'cwd': os.getcwd()}) + '\n')
if '--version' in args:
    print('fixture-quint (not a real tool)')
elif args[0] == 'run':
    # 按请求列表伪造计数，允许缺失/零值注入，检查 validator 是否拒绝覆盖缺口。
    start = args.index('--witnesses') + 1
    for name in args[start:]:
        if name.startswith('--'):
            break
        if name == os.environ.get('QUINT_FIXTURE_MISSING'):
            continue
        count = 0 if name == os.environ.get('QUINT_FIXTURE_ZERO') else 3
        print(f'{name} was witnessed in {count} trace(s) out of 10000 explored')
elif args[0] == 'verify':
    backend = Path('_apalache-out/server/fixture/detailed.log')
    backend.parent.mkdir(parents=True, exist_ok=True)
    backend.write_text('fixture-local checkpoint; no model check\n')
    if os.environ.get('QUINT_FIXTURE_HANG') == '1':
        # 普通子进程继承本组，模拟包装器超时回收；假 checkpoint 不代表有界检查结果。
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
        Path(os.environ['QUINT_FIXTURE_PIDS']).write_text(f'{os.getpid()} {child.pid}')
        time.sleep(60)
if os.environ.get('QUINT_FIXTURE_FAIL') == (args[0] if args else ''):
    print('fixture deliberate failure', file=sys.stderr)
    sys.exit(7)
