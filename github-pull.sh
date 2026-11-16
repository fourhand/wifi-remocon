#!/bin/bash
# GitHub main 최신 커밋을 받아 반영한다. (구현은 github-pull.py)
set -euo pipefail
cd "$(dirname "$0")"
exec /usr/bin/python3 ./github-pull.py "$@"
