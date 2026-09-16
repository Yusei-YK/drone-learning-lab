#!/usr/bin/python3
"""只读检查磁盘与 MemAvailable；不足时拒绝启动。"""
import os
from pathlib import Path
import shutil
import sys
import re

GIB = 1024 ** 3


def mount_for(path):
    """查宿主机挂载表；不可访问目录不得回退到另一块文件系统。"""
    mounts = []
    for line in Path('/proc/self/mountinfo').read_text().splitlines():
        mount = re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), line.split()[4])
        candidate = Path(mount)
        if path == candidate or candidate in path.parents:
            mounts.append(candidate)
    return max(mounts, key=lambda p: len(str(p)))


def check(paths, memory_gib):
    memory = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
    available = int(memory['MemAvailable'].split()[0]) * 1024
    problems = []
    if available < memory_gib * GIB:
        problems.append(f'MemAvailable={available / GIB:.2f} GiB，需要至少 {memory_gib} GiB')
    # Docker root 常需 root 权限。沿父目录找到可 stat 的同文件系统路径；
    # 检查根分区之外也检查工作区，避免把 /home 与 /var 当成同一分区。
    for original in paths:
        path = Path(original)
        if not path.is_absolute():
            raise ValueError(f'需要绝对路径：{path}')
        boundary = mount_for(path)
        while not os.access(path, os.X_OK) and path != boundary:
            path = path.parent
        if not os.access(path, os.X_OK):
            raise RuntimeError(f'无法检查 {original} 所在文件系统，拒绝启动')
        free = shutil.disk_usage(path).free
        print(f'{original}: 可查询路径 {path}，可用 {free / GIB:.2f} GiB')
        if free < 15 * GIB:
            problems.append(f'{path} 可用 {free / GIB:.2f} GiB，需要至少 15 GiB')
    print(f'MemAvailable={available / GIB:.2f} GiB')
    if problems:
        raise RuntimeError('拒绝启动：' + '；'.join(problems))


if __name__ == '__main__':
    try:
        check(sys.argv[1:3], int(sys.argv[3]))
    except (OSError, ValueError, RuntimeError) as exc:
        sys.exit(str(exc))
