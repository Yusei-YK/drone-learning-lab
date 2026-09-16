#!/usr/bin/env bash
# 固定 PX4 v1.16.0 / X500 单套仿真验收；禁止用于真机。
set -euo pipefail
ulimit -c 0
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export PX4_ROOT="$HOME/Documents/Codex/px4-sitl-1.16"
export PX4_IMAGE=local/px4-humble-116:latest
export PX4_SIM_CONTAINER=px4_sitl_116
export PX4_MAVROS_CONTAINER=px4_mavros_116
export PX4_SESSION_SECONDS=360
export DDS_INTERFACE=lo
D=(sudo -n /usr/bin/docker)
EVIDENCE="${1:?请指定一个新的证据目录}"
mkdir "$EVIDENCE"
EVIDENCE="$(cd "$EVIDENCE" && pwd)"
source_dir="$PX4_ROOT/PX4-Autopilot"
[[ "$(git -C "$source_dir" rev-parse HEAD)" == 6ea3539157ca358c70a515878b77077af7d4611d ]]
[[ "$(git -C "$source_dir/Tools/simulation/gz" rev-parse HEAD)" == e05f4312d3f28aa621157610584a4870406cb6d3 ]]
git -C "$source_dir" diff --quiet HEAD -- ROMFS/px4fmu_common/init.d-posix/airframes/4001_gz_x500
# 不删除用户或其他会话已有的容器。
for c in "$PX4_SIM_CONTAINER" "$PX4_MAVROS_CONTAINER"; do
  if "${D[@]}" inspect "$c" >/dev/null 2>&1; then
    echo "已有 $c，拒绝接管。" >&2
    exit 1
  fi
done
qgc_pid=''
cleanup() {
  local code=$?
  trap - EXIT
  set +e
  for c in "$PX4_SIM_CONTAINER" "$PX4_MAVROS_CONTAINER"; do
    if "${D[@]}" inspect "$c" >/dev/null 2>&1; then
      /usr/bin/python3 "$SCRIPT_DIR/bounded-logs.py" "$c" 200 > "$EVIDENCE/$c.log" 2>&1
      "${D[@]}" inspect --format '{{json .HostConfig.LogConfig}} {{.HostConfig.Memory}} {{.HostConfig.MemorySwap}} {{json .State}}' "$c" > "$EVIDENCE/$c-limits.txt"
    fi
  done
  bash "$SCRIPT_DIR/run-sitl.sh" stop || code=1
  for c in "$PX4_SIM_CONTAINER" "$PX4_MAVROS_CONTAINER"; do
    if "${D[@]}" inspect "$c" >/dev/null 2>&1; then
      echo "清理未完成：$c 仍存在。" >&2
      code=1
    fi
  done
  if [[ -n "$qgc_pid" ]]; then
    kill -TERM "$qgc_pid" 2>/dev/null
    wait "$qgc_pid" 2>/dev/null
  fi
  { df -h /; free -h; "${D[@]}" ps -a; } > "$EVIDENCE/resources-after.txt"
  printf 'exit_code=%s\n' "$code" > "$EVIDENCE/result.txt"
  echo "验收退出码=$code；证据目录：$EVIDENCE"
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# 已有桌面 QGC 时复用；只关闭本脚本启动的实例。
if ! pgrep -x QGroundControl >/dev/null; then
  : "${DISPLAY:?需要桌面 DISPLAY 以启动地面站}"
  timeout --signal=TERM --kill-after=5s 330s \
    "$HOME/Applications/QGroundControl/AppRun" >/dev/null 2>&1 &
  qgc_pid=$!
fi
bash "$SCRIPT_DIR/run-sitl.sh" start
bash "$SCRIPT_DIR/run-sitl.sh" mavros
"${D[@]}" exec -i "$PX4_SIM_CONTAINER" sh -c 'cat > /tmp/accept-flight.py' < "$SCRIPT_DIR/accept-flight.py"
# 只限制证据写入进程，不能让 QGC 的正常缓存文件继承这个限制。
(
  ulimit -f 2048
  "${D[@]}" exec "$PX4_SIM_CONTAINER" bash -c \
    'source /opt/ros/humble/setup.bash; exec timeout --signal=TERM --kill-after=5s 190s /usr/bin/python3 /tmp/accept-flight.py'
) > "$EVIDENCE/flight.jsonl" 2>&1
# 既要求进程成功退出，也要求有最终 PASS；服务 ACK 不算通过。
/usr/bin/python3 - "$EVIDENCE/flight.jsonl" <<'PY'
import json, sys
from pathlib import Path
rows = [json.loads(s) for s in Path(sys.argv[1]).read_text().splitlines() if s.startswith('{')]
assert rows[-1].get('event') == 'PASS', '没有完成全部验收'
print(json.dumps(rows[-1], ensure_ascii=False))
PY
