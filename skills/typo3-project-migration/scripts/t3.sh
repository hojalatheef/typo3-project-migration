#!/usr/bin/env bash
# t3.sh — run the TYPO3 console of the project in the current directory, the
# way this project runs it: inside DDEV when the project is a DDEV project and
# we are on the host, otherwise directly.
#
# Usage: t3.sh [--print] <typo3 command> [args...]
#   t3.sh upgrade:list
#   t3.sh --print cache:flush      # only print the command that would run
#
# Binary lookup (first hit wins):
#   1. <bin-dir from composer.json config.bin-dir, default vendor/bin>/typo3
#   2. typo3/sysext/core/bin/typo3 or public/typo3/sysext/core/bin/typo3 (classic mode)
#   3. vendor/bin/typo3cms (helhum/typo3-console on old projects)
# Exit code: the command's own, or 2 if no TYPO3 binary was found.

set -euo pipefail

print=0
if [[ "${1:-}" == "--print" ]]; then print=1; shift; fi
if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then sed -n '2,14p' "$0"; exit 0; fi

bin_dir="vendor/bin"
if [[ -f composer.json ]] && command -v jq >/dev/null; then
  bin_dir="$(jq -r '.config["bin-dir"] // "vendor/bin"' composer.json 2>/dev/null || echo vendor/bin)"
fi

binary=""
for b in "$bin_dir/typo3" typo3/sysext/core/bin/typo3 public/typo3/sysext/core/bin/typo3 "$bin_dir/typo3cms"; do
  [[ -e "$b" ]] && { binary="$b"; break; }
done
[[ -n "$binary" ]] || { echo "t3.sh: no TYPO3 console found (looked in $bin_dir, typo3/sysext/core/bin, public/typo3/sysext/core/bin). Run composer install first." >&2; exit 2; }

cmd=()
# On the host of a DDEV project, the console must run with the container's PHP and database.
if [[ -f .ddev/config.yaml && -z "${IS_DDEV_PROJECT:-}" ]] && command -v ddev >/dev/null; then
  cmd=(ddev exec "$binary")
else
  cmd=(php "$binary")
fi
cmd+=("$@")

if (( print )); then printf '%q ' "${cmd[@]}"; echo; exit 0; fi
exec "${cmd[@]}"
