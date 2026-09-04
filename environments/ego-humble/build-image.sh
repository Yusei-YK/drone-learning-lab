#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
exec sudo docker build -t local/ego-planner-humble:latest .
