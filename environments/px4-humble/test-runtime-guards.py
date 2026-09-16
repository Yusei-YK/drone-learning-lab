#!/usr/bin/python3
"""防止日志刷屏、等待不退出、缺少容器限额；不启动 PX4/Gazebo。"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


logs = load('bounded_logs', 'bounded-logs.py')
resources = load('resources', 'check-resources.py')


class Guards(unittest.TestCase):
    def test_long_line_is_bounded(self):
        data, reason, _ = logs.read_bounded([
            sys.executable, '-c', 'import os; os.write(1, b"pxh> " * 400000)'
        ])
        self.assertEqual(len(data), 65536)
        self.assertEqual(reason, '字节')

    def test_silent_command_is_terminated(self):
        start = time.monotonic()
        data, reason, status = logs.read_bounded([
            sys.executable, '-c', 'import time; time.sleep(60)'
        ], seconds=0.2)
        self.assertEqual(data, b'')
        self.assertEqual(reason, '时间')
        self.assertNotEqual(status, 0)
        self.assertLess(time.monotonic() - start, 2)

    def test_command_failure_is_reported(self):
        data, reason, status = logs.read_bounded([
            sys.executable, '-c', 'print("missing container"); raise SystemExit(7)'
        ])
        self.assertIn(b'missing container', data)
        self.assertIsNone(reason)
        self.assertEqual(status, 7)

    def test_memory_refuses_start(self):
        with patch.object(resources.Path, 'read_text', return_value='MemAvailable: 1024 kB\n'), \
             patch.object(resources, 'mount_for', return_value=Path('/')):
            with self.assertRaisesRegex(RuntimeError, 'MemAvailable'):
                resources.check(['/'], 4)

    def test_low_disk_refuses_start(self):
        usage = type('Usage', (), {'free': 2 * resources.GIB})()
        with patch.object(resources.shutil, 'disk_usage', return_value=usage):
            with self.assertRaisesRegex(RuntimeError, '15 GiB'):
                resources.check(['/'], 0)

    def test_runner_has_limits_and_no_interactive_shell(self):
        # 以假 docker 记录实际传参，不创建容器、不启动飞行。
        with tempfile.TemporaryDirectory(prefix='px4-guard-test-') as tmp:
            tmp = Path(tmp)
            build = tmp / 'PX4-Autopilot/build/px4_sitl_default'
            (build / 'bin').mkdir(parents=True)
            (build / 'rootfs').mkdir()
            (build / 'etc').mkdir()
            (build / 'bin/px4').write_text('#!/bin/sh\nexit 99\n')
            (build / 'bin/px4').chmod(0o755)
            (build / 'rootfs/gz_env.sh').touch()
            fake = tmp / 'fake'
            fake.mkdir()
            sudo = fake / 'sudo'
            sudo.write_text('''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
a=sys.argv[3:]
if a[0]=='info': print('/var/lib/docker')
elif a[:2]==['container','inspect']: sys.exit(1)
elif a[0]=='ps': pass
elif a[0]=='run':
 Path(os.environ['GUARD_CAPTURE']).write_text(json.dumps(a))
 print('fake-container-id')
else: sys.exit('unexpected docker call')
''')
            sudo.chmod(0o755)
            pgrep = fake / 'pgrep'
            pgrep.write_text('#!/bin/sh\nexit 1\n')
            pgrep.chmod(0o755)
            env = dict(os.environ, PATH=str(fake) + ':' + os.environ['PATH'],
                       PX4_ROOT=str(tmp), PX4_GUI='0', GUARD_CAPTURE=str(tmp / 'args.json'))
            env.pop('DISPLAY', None)
            result = subprocess.run(['bash', str(HERE / 'run-sitl.sh'), 'start'],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            args = json.loads((tmp / 'args.json').read_text())
            for flag in ['--memory=3g', '--memory-swap=3g', '--cpus=4', '--restart=no',
                         '--read-only', 'core=0', 'max-size=10m', 'max-file=2']:
                self.assertIn(flag, args)
            self.assertIn('--kill-after=5s', args[-1])
            self.assertIn('"$build/bin/px4" -d -w /px4-runtime', args[-1])
            self.assertNotIn('make px4_sitl', args[-1])
            self.assertTrue(any('/px4-runtime:rw,size=256m' in arg for arg in args))


if __name__ == '__main__':
    unittest.main(verbosity=2)
