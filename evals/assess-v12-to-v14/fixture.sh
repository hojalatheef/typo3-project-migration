#!/usr/bin/env bash
set -euo pipefail
cp -R "$(cd "$(dirname "$0")/../fixtures/project_v12" && pwd)/." .
git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.invalid commit -qm init
