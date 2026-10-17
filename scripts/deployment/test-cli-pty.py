#!/usr/bin/env python3
"""Real Unicode terminal IO, finite deadlines and process-group cleanup."""
import errno
import os
import pty
import select
import signal
import subprocess
import time


def terminal(argv, payload, *, cwd, env, timeout=25):
    master, slave = pty.openpty()
    process = None
    data = bytearray()
    try:
        process = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave,
                                   cwd=cwd, env=env, start_new_session=True)
        os.close(slave)
        slave = -1
        pending = memoryview(payload)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            readable, writable, _ = select.select([master], [master] if pending else [], [], .05)
            if writable:
                pending = pending[os.write(master, pending[:256]):]
            if readable:
                try:
                    chunk = os.read(master, 8192)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
                if not chunk:
                    break
                data.extend(chunk)
                if len(data) > 2_000_000:
                    raise AssertionError('terminal output limit')
            if process.poll() is not None and not readable:
                break
        else:
            raise TimeoutError('terminal deadline')
        return process.wait(timeout=2), bytes(data)
    finally:
        os.close(master)
        if slave >= 0:
            os.close(slave)
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)


if __name__ == '__main__':
    import base64
    import pathlib
    root = pathlib.Path(__file__).resolve().parents[2]
    env = dict(os.environ, ERL_FLAGS='+S 2:2')
    # Each result is produced after the reader returns, independent of TTY echo.
    for text in ['ASCII  ', 'café', '中国', 'é😀', '  spaces  ']:
        code = 'before = :io.getopts(:standard_io); v = Beamlet.CLI.Runner.read_line(:stdio); ^before = :io.getopts(:standard_io); IO.puts("READ=" <> Base.encode64(v))'
        status, output = terminal(['elixir', '-pa', os.environ.get('BEAMLET_READER_EBIN', '_build/test/lib/beamlet_cli/ebin'), '-e', code],
                                  (text + '\n').encode(), cwd=root, env=env)
        assert status == 0 and b'READ=' + base64.b64encode(text.encode()) in output, output
    code = 'before = :io.getopts(:standard_io); {:error, :input} = Beamlet.CLI.Runner.read_line(:stdio); ^before = :io.getopts(:standard_io); IO.puts("INVALID_REJECTED")'
    status, output = terminal(['elixir', '-pa', os.environ.get('BEAMLET_READER_EBIN', '_build/test/lib/beamlet_cli/ebin'), '-e', code],
                              b'\xff\n', cwd=root, env=env)
    assert status == 0 and b'INVALID_REJECTED' in output, output
    print('Real PTY exact UTF-8 reader: 5 valid vectors, invalid bytes rejected, options restored')
