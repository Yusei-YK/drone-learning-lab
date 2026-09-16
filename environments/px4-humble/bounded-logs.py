#!/usr/bin/python3
"""读取 Docker 日志时同时限制行数、字节和时间，避免超长单行挤满终端。"""
import os
import selectors
import subprocess
import sys
import time

MAX_BYTES = 65536
MAX_SECONDS = 8


def read_bounded(command, limit=MAX_BYTES, seconds=MAX_SECONDS):
    output = bytearray()
    reason = None
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as proc:
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(proc.stdout, selectors.EVENT_READ)
                deadline = time.monotonic() + seconds
                while len(output) < limit:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0 or not selector.select(remaining):
                        reason = '时间'
                        break
                    block = os.read(proc.stdout.fileno(), min(4096, limit - len(output)))
                    if not block:
                        break
                    output.extend(block)
                if len(output) == limit:
                    reason = '字节'
        finally:
            if proc.poll() is None:
                proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
    return bytes(output), reason, proc.returncode


if __name__ == '__main__':
    if len(sys.argv) != 3 or not sys.argv[2].isdigit() or not 1 <= int(sys.argv[2]) <= 200:
        sys.exit('用法：bounded-logs.py 容器名 行数（1..200）')
    data, reason, status = read_bounded([
        'sudo', '-n', '/usr/bin/docker', 'logs', '--tail', sys.argv[2], sys.argv[1]
    ])
    # 使用文本输出，避免控制字符不断清屏；总读取量已受 MAX_BYTES 限制。
    sys.stdout.write(data.decode('utf-8', errors='replace').replace('\r', '\n').replace('\x1b', '<ESC>'))
    if reason:
        print(f'\n[已达到{reason}上限，停止读取；没有跟随日志。]')
    sys.exit(0 if reason else status)
