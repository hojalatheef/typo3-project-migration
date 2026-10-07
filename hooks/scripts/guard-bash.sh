#!/usr/bin/env bash
# guard-bash.sh — PreToolUse hook for Bash.
#
# A project upgrade is revertible with git until the first command that writes
# the database. This hook keeps that line visible:
#   * deny  typo3 extension:setup / upgrade:run / upgrade:mark:undone /
#           database:updateschema (also via t3.sh or ddev) unless a database
#           dump younger than 24 h exists in .project-migration/backups/ or
#           .ddev/db_snapshots/
#   * ask   destructive schema changes (database:updateschema with "*" or
#           *.remove/*.drop/destructive), ddev import-db, ddev delete,
#           DROP DATABASE/TABLE, TRUNCATE
#   * deny  git commit/push with --no-verify, composer --ignore-platform-req(s)
#           on install/update/require
# Everything else passes through. Reads the hook payload on stdin.

set -euo pipefail

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
[[ -z "$cmd" ]] && exit 0
[[ -n "$cwd" && -d "$cwd" ]] && cd "$cwd"

decide() {
  jq -n --arg d "$1" --arg reason "$2" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: $d,
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}
has() { printf '%s' "$cmd" | command grep -Eiq -- "$1"; }

# --- shortcuts that hide a failure
if has 'git[[:space:]][^|;&]*--no-verify' || has 'git[[:space:]]+commit[^|;&"'\'']*[[:space:]]-[a-mo-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'; then
  decide deny "typo3-project-migration: skipping git hooks is not allowed. Run what the hook runs, fix what it reports, then commit again."
fi
if has 'composer[[:space:]]+(install|update|require|upgrade|u|i)[[:space:]][^|;&]*--ignore-platform-req'; then
  decide deny "typo3-project-migration: --ignore-platform-req(s) produces a lock file for a PHP or extension set nobody runs. Raise PHP where the site runs (e.g. php_version in .ddev/config.yaml, then ddev restart) and resolve again."
fi

# --- destructive database operations: always the user's call
if has '(typo3|typo3cms|t3\.sh)[[:space:]]+[^|;&]*database:updateschema[^|;&]*(\*|\.remove|\.drop|destructive)' \
   || has 'ddev[[:space:]]+(import-db|delete)' \
   || has '(drop[[:space:]]+(database|schema|table)|truncate[[:space:]]+(table[[:space:]]+)?[a-z_`])'; then
  decide ask "typo3-project-migration: this removes or replaces database content and cannot be undone with git. Confirm only if a current dump exists and this is the copy, not production."
fi

# --- writes to the database: need a recent dump first
if has '(typo3|typo3cms|t3\.sh)[[:space:]]+[^|;&]*(extension:setup|upgrade:run|upgrade:mark:undone|database:updateschema)'; then
  recent="$(find .project-migration/backups .ddev/db_snapshots -maxdepth 1 -mmin -1440 \
    \( -name '*.sql' -o -name '*.sql.gz' -o -name '*.sql.bz2' -o -name '*.sql.zst' -o -name '*.dump' -o -name '*.gz' -o -name '*.zst' \) \
    2>/dev/null | head -1 || true)"
  if [[ -z "$recent" ]]; then
    decide deny "typo3-project-migration: no database dump from the last 24 h in .project-migration/backups/ or .ddev/db_snapshots/. This command writes the database (schema, wizards), which git cannot revert. Take one first, e.g. 'ddev snapshot --name pre-v13' or 'ddev export-db --file=.project-migration/backups/pre-v13.sql.gz' (or mysqldump/pg_dump into that folder), then run it again."
  fi
fi

exit 0
