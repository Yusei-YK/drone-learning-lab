#!/usr/bin/python3
"""Prepare a reproducible, namespaced px4ctrl copy; never modify upstream."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile

COMMIT = '85032f11e5f325678cee5c029676c43931281d36'
upstream = Path(os.environ.get('PX4CTRL_SOURCE', str(Path.home() / 'Documents/Codex/px4ctrl-ros2/px4ctrl-ros2-fast-drone')))
workspace = Path(os.environ.get('INTEGRATION_WS', str(Path.home() / 'Documents/Codex/drone-integration')))
assert subprocess.check_output(['git', '-C', str(upstream), 'rev-parse', 'HEAD'], text=True).strip() == COMMIT, 'upstream commit mismatch'
archive = subprocess.check_output(['git', '-C', str(upstream), 'archive', COMMIT])
files = {}
with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
    for member in tar.getmembers():
        name = member.name
        if not member.isfile():
            continue
        if name == 'LICENSE':
            files['UPSTREAM-LICENSE'] = tar.extractfile(member).read()
        elif name.startswith(('src/px4ctrl/', 'src/quadrotor_msgs/')):
            data = tar.extractfile(member).read()
            target = name.replace('quadrotor_msgs', 'px4ctrl_msgs')
            files[target] = data.replace(b'quadrotor_msgs', b'px4ctrl_msgs')
            if target == 'src/px4ctrl/src/PX4CtrlFSM.cpp':
                old = b'rclcpp::Duration(AutoTakeoffLand_t::DELAY_TRIGGER_TIME)'
                assert files[target].count(old) == 1
                files[target] = files[target].replace(old, b'rclcpp::Duration::from_seconds(AutoTakeoffLand_t::DELAY_TRIGGER_TIME)')
manifest = {'upstream': 'https://github.com/Ethan-02/px4ctrl-ros2-fast-drone', 'commit': COMMIT,
            'transformation': 'quadrotor_msgs -> px4ctrl_msgs; Duration::from_seconds; generated copy only',
            'sha256': {p: hashlib.sha256(data).hexdigest() for p, data in files.items()}}
manifest_path = workspace / 'source-manifest.json'
if workspace.exists():
    assert manifest_path.exists(), 'unmanaged workspace; refusing overwrite'
    previous = json.loads(manifest_path.read_text())
    for name, digest in previous['sha256'].items():
        assert hashlib.sha256((workspace / name).read_bytes()).hexdigest() == digest, f'local edits in {name}; refusing overwrite'
else:
    workspace.mkdir(parents=True)
for name, data in files.items():
    target = workspace / name
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists() or target.read_bytes() != data:
        target.write_bytes(data)
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Prepared {workspace} at {COMMIT}; original source unchanged.')
