#!/usr/bin/env bash
# project-gate.sh — prove one hop of a TYPO3 project upgrade with measured
# results and one verdict.
#
# Usage: project-gate.sh --target <major> [--baseline <label>] [--skip a,b] [project-dir]
#
# Steps (each PASS, FAIL or SKIPPED with a reason, never silently passed):
#   core       installed core major == --target
#   composer   composer validate (Composer mode)
#   platform   composer check-platform-reqs, run where the site runs (DDEV aware)
#   console    the TYPO3 console boots: t3.sh list
#   cache      t3.sh cache:flush
#   wizards    t3.sh upgrade:list reports "No wizards available."
#   smoke      smoke-test.sh capture + compare against --baseline (default: baseline)
#   errorlog   no new ERROR/CRITICAL/ALERT/EMERGENCY lines in var/log/typo3_*.log
#              while the gate ran (needs smoke to have produced traffic)
# Also reported, not judged: new deprecation log lines.
#
# Exit 0 only if nothing FAILED. A SKIPPED line is a gap, not a pass.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target=""; baseline="baseline"; skip=""; dir="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) target="$2"; shift 2 ;;
    --baseline) baseline="$2"; shift 2 ;;
    --skip) skip="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) dir="$1"; shift ;;
  esac
done
[[ "$target" =~ ^1[0-5]$ ]] || { echo "project-gate.sh: --target <major> is required (10-15)" >&2; exit 2; }
cd "$dir" || exit 2

declare -a names=() verdicts=()
failed=0
logs="$(mktemp -d)"
wanted() { [[ ",$skip," != *",$1,"* ]]; }
record() { names+=("$1"); verdicts+=("$2"); [[ "$2" == FAIL* ]] && failed=1; return 0; }
skipped() { wanted "$1" && record "$1" "SKIPPED: $2"; }
step() {
  local name="$1"; shift
  wanted "$name" || return 0
  printf '── %-9s %s\n' "$name" "$*"
  if "$@" >"$logs/$name.log" 2>&1; then record "$name" PASS
  else
    record "$name" "FAIL (exit $?)"
    tail -n 20 "$logs/$name.log" | sed 's/^/   │ /'
  fi
}

on_ddev_host() { [[ -f .ddev/config.yaml && -z "${IS_DDEV_PROJECT:-}" ]] && command -v ddev >/dev/null; }
composer_cmd() { if on_ddev_host; then ddev composer "$@"; else composer "$@"; fi; }

inv="$("$here/inventory.sh" --json 2>/dev/null || echo '{}')"
mode="$(jq -r '.mode // "unknown"' <<<"$inv")"
major="$(jq -r '.core.major // empty' <<<"$inv")"

# core
if wanted core; then
  if [[ "$major" == "$target" ]]; then record core "PASS ($(jq -r .core.installed <<<"$inv"))"
  else record core "FAIL (installed: $(jq -r '.core.installed // "none"' <<<"$inv"), target: $target)"; fi
fi

# composer + platform
if [[ "$mode" == composer ]]; then
  step composer composer_cmd validate --no-check-publish --no-interaction
  step platform composer_cmd check-platform-reqs --no-interaction
else
  skipped composer "classic mode (no composer.json requiring typo3/cms-*)"
  skipped platform "classic mode"
fi

# console, cache, wizards
step console "$here/t3.sh" list
step cache "$here/t3.sh" cache:flush
if wanted wizards; then
  printf '── %-9s %s\n' wizards "t3.sh upgrade:list"
  if "$here/t3.sh" upgrade:list >"$logs/wizards.log" 2>&1; then
    if command grep -q 'No wizards available' "$logs/wizards.log"; then record wizards PASS
    else
      record wizards "FAIL (wizards pending, see below)"
      sed 's/^/   │ /' "$logs/wizards.log" | head -40
    fi
  else
    record wizards "FAIL (upgrade:list exit $?)"; tail -n 20 "$logs/wizards.log" | sed 's/^/   │ /'
  fi
fi

# error log watermark before traffic
log_dir="var/log"; [[ -d "$log_dir" ]] || log_dir="typo3temp/var/log"
declare -a log_files=() log_sizes=()
for f in "$log_dir"/typo3_*.log; do
  [[ -f "$f" ]] || continue
  log_files+=("$f"); log_sizes+=("$(wc -c < "$f" | tr -d ' ')")
done

# smoke
smoke_ran=0
if wanted smoke; then
  if [[ ! -f .project-migration/urls.txt ]]; then skipped smoke "no .project-migration/urls.txt (run smoke-test.sh seed)"
  elif [[ ! -f ".project-migration/smoke/$baseline.tsv" ]]; then skipped smoke "no baseline capture '$baseline' (capture it before the hop)"
  else
    label="gate-v$target-$(date +%Y%m%d-%H%M%S)"
    printf '── %-9s %s\n' smoke "capture $label, compare with $baseline"
    "$here/smoke-test.sh" capture "$label" >"$logs/smoke-capture.log" 2>&1
    smoke_ran=1
    if "$here/smoke-test.sh" compare "$baseline" "$label" >"$logs/smoke.log" 2>&1; then record smoke "PASS ($(tail -1 "$logs/smoke.log"))"
    else record smoke "FAIL ($(tail -1 "$logs/smoke.log"))"; command grep -E '^(REGRESS|BROKEN|NEW)' "$logs/smoke.log" | head -30 | sed 's/^/   │ /'; fi
  fi
fi

# error log: what was appended while the gate ran
new_dep=0
if wanted errorlog; then
  if (( smoke_ran == 0 )); then skipped errorlog "no smoke traffic to judge the log by"
  elif (( ${#log_files[@]} == 0 )); then skipped errorlog "no $log_dir/typo3_*.log files"
  else
    : > "$logs/errorlog.log"
    for i in "${!log_files[@]}"; do
      tail -c +"$((log_sizes[i] + 1))" "${log_files[$i]}" >> "$logs/new-log-lines.log" 2>/dev/null || true
    done
    for f in "$log_dir"/typo3_*.log; do
      # A log file created during the run was not in the watermark list.
      known=0; for k in "${log_files[@]}"; do [[ "$k" == "$f" ]] && known=1; done
      (( known )) || cat "$f" >> "$logs/new-log-lines.log"
    done
    command grep -E '\[(ERROR|CRITICAL|ALERT|EMERGENCY)\]' "$logs/new-log-lines.log" > "$logs/errorlog.log" || true
    new_dep="$(command grep -c -i 'deprecat' "$logs/new-log-lines.log" 2>/dev/null || true)"
    n="$(wc -l < "$logs/errorlog.log" | tr -d ' ')"
    if [[ "$n" == 0 ]]; then record errorlog PASS
    else record errorlog "FAIL ($n new error line(s))"; head -15 "$logs/errorlog.log" | cut -c1-240 | sed 's/^/   │ /'; fi
  fi
fi

echo
echo "Project gate summary, target v$target ($(pwd))"
for i in "${!names[@]}"; do printf '  %-9s %s\n' "${names[$i]}" "${verdicts[$i]}"; done
[[ "${new_dep:-0}" != 0 ]] && echo "  info      ${new_dep} new deprecation log line(s) — work for the next hop"
echo "  logs: $logs"
echo "  not covered here: backend login and modules, editor workflows, scheduler runs, mail, own extensions' test suites"
if (( failed )); then echo "VERDICT: FAILED"; exit 1; fi
echo "VERDICT: PASSED (read SKIPPED lines before calling the hop done)"
