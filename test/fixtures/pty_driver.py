"""Drive a fixture CLI through a real POSIX PTY, with stdout captured separately."""

import fcntl
import json
import os
import pty
import select
import struct
import subprocess
import sys
import termios
import time

request = json.load(sys.stdin)
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 32, 120, 0, 0))
output = b""
sent = False
child = None
try:
    with open(request["captured"], "wb") as captured:
        child = subprocess.Popen(
            request["args"],
            stdin=slave,
            stdout=captured,
            stderr=slave,
            env={**os.environ, **request["env"]},
            start_new_session=True,
        )
        os.close(slave)
        slave = None
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            readable, _, _ = select.select([master], [], [], 0.05)
            if readable:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
                if not sent and "sessions · ready".encode() in output:
                    sent = True
                    os.write(master, request["key"].encode("latin1"))
            if child.poll() is not None and not readable:
                break
        if child.poll() is None:
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
                raise RuntimeError("Picker or fixture timed out") from None
        print(
            json.dumps(
                {
                    "status": child.returncode,
                    "sent": sent,
                    "output": output.decode(errors="replace"),
                }
            )
        )
finally:
    if child is not None and child.poll() is None:
        child.kill()
        child.wait()
    os.close(master)
    if slave is not None:
        os.close(slave)
