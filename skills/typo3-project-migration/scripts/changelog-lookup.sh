#!/usr/bin/env bash
# changelog-lookup.sh — print the official TYPO3 core changelog entry for a
# changelog id, issue number or keyword, instead of recalling it from memory.
#
# Usage: changelog-lookup.sh <query> [--path DIR] [--version 12.0] [--list] [--max N] [--no-fetch]
#
#   <query>    Breaking-98443-ExtensionRecordlistMergedIntoBackend, 98443, or a
#              keyword such as switchableControllerActions (matched in the text)
#   --path     project root to look for vendor copies in (default: .)
#   --version  only search one changelog folder, e.g. 12.0 or 13.4
#   --list     only print matching files with their titles, not the full text
#   --max      print at most N entries in full (default 3; lists show up to 10 x N)
#   --no-fetch never clone typo3/typo3; use vendor copies and the cache only
#
# Sources, first one with a match wins:
#   1. <path>/vendor/typo3/cms-core/Documentation/Changelog (Composer mode)
#   2. <path>/typo3_src/typo3/sysext/core/... or <path>/public/typo3/sysext/core/...
#      (classic mode)
#   3. a sparse clone of github.com/TYPO3/typo3 (changelogs only) cached in
#      ${XDG_CACHE_HOME:-~/.cache}/typo3-project-migration/typo3-core; an
#      existing clone from the typo3-extension-migration plugin is reused
# A vendor copy only holds the changelogs its core version ships, so ids from
# older majors usually come from the cache. Exit code: 0 = found,
# 1 = nothing found, 2 = usage or fetch error.

set -euo pipefail

query=""
path="."
version=""
list=0
max=3
fetch=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) path="$2"; shift 2 ;;
    --version) version="$2"; shift 2 ;;
    --list) list=1; shift ;;
    --max) max="$2"; shift 2 ;;
    --no-fetch) fetch=0; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    -*) echo "unknown argument: $1" >&2; exit 2 ;;
    *) [[ -z "$query" ]] || { echo "only one query allowed" >&2; exit 2; }; query="$1"; shift ;;
  esac
done

[[ -n "$query" ]] || { echo "a changelog id, issue number or keyword is required" >&2; exit 2; }
[[ "$max" =~ ^[1-9][0-9]*$ ]] || { echo "--max must be a positive number" >&2; exit 2; }

cache="${XDG_CACHE_HOME:-$HOME/.cache}/typo3-project-migration/typo3-core"
sibling="${XDG_CACHE_HOME:-$HOME/.cache}/typo3-extension-migration/typo3-core"
# One sparse clone per machine is enough: reuse the sister plugin's if it exists.
[[ ! -d "$cache/.git" && -d "$sibling/.git" ]] && cache="$sibling"
cache_changelog="$cache/typo3/sysext/core/Documentation/Changelog"

fetch_cache() {
  command -v git >/dev/null || { echo "git is needed to fetch the core changelogs" >&2; return 1; }
  if [[ -d "$cache/.git" ]]; then
    # Refresh at most once a day.
    if [[ -n "$(find "$cache/.git/FETCH_HEAD" -mmin -1440 2>/dev/null)" ]]; then return 0; fi
    git -C "$cache" pull --quiet --depth 1 >&2 || echo "warning: could not update $cache, using the cached copy" >&2
  else
    echo "fetching core changelogs into $cache (once)..." >&2
    mkdir -p "$(dirname "$cache")"
    if ! { git clone --quiet --depth 1 --filter=blob:none --sparse https://github.com/TYPO3/typo3.git "$cache" >&2 \
        && git -C "$cache" sparse-checkout set typo3/sysext/core/Documentation/Changelog >&2; }; then
      rm -rf "$cache"
      echo "could not clone typo3/typo3" >&2
      return 1
    fi
    touch "$cache/.git/FETCH_HEAD"
  fi
}

# Entry files only (Breaking-*, Deprecation-*, Feature-*, Important-*), no index pages.
entries() {
  local dir="$1"
  [[ -n "$version" ]] && dir="$dir/$version"
  [[ -d "$dir" ]] || return 0
  find "$dir" -type f -name '*.rst' \
    \( -name 'Breaking-*' -o -name 'Deprecation-*' -o -name 'Feature-*' -o -name 'Important-*' \)
}

search() {
  local dir="$1"
  if [[ "$query" =~ ^(Breaking|Deprecation|Feature|Important)-[0-9]+ ]]; then
    # Full id: an exact file wins; otherwise match type and number, since the
    # title part may differ in spelling or one issue may have several entries.
    local all exact
    all="$(entries "$dir" | grep -F "/${BASH_REMATCH[0]}-" || true)"
    exact="$(printf '%s\n' "$all" | grep -F "/${query%.rst}.rst" || true)"
    printf '%s\n' "${exact:-$all}" | sed '/^$/d'
  elif [[ "$query" =~ ^#?[0-9]{4,6}$ ]]; then
    entries "$dir" | grep -E "/[A-Za-z]+-${query#\#}-" || true
  else
    entries "$dir" | tr '\n' '\0' | xargs -0 grep -liF -- "$query" 2>/dev/null || true
  fi
}

sources=("$path/vendor/typo3/cms-core/Documentation/Changelog"
         "$path/typo3_src/typo3/sysext/core/Documentation/Changelog"
         "$path/public/typo3/sysext/core/Documentation/Changelog"
         "$cache_changelog")

matches=""
source_dir=""
for dir in "${sources[@]}"; do
  if [[ "$dir" == "$cache_changelog" && "$fetch" == 1 ]]; then
    fetch_cache || [[ -d "$dir" ]] || exit 2
  fi
  [[ -d "$dir" ]] || continue
  matches="$(search "$dir" | sort)"
  [[ -n "$matches" ]] && { source_dir="$dir"; break; }
done

if [[ -z "$matches" ]]; then
  echo "No changelog entry matches '$query'${version:+ in $version}." >&2
  if [[ "$fetch" == 0 ]]; then echo "Retry without --no-fetch to search every core version." >&2; fi
  exit 1
fi

total="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
title() { grep -m1 -E '^(Breaking|Deprecation|Feature|Important): ' "$1" || basename "$1" .rst; }

echo "Source: $source_dir ($total match(es))"
if (( list || total > max )); then
  (( list )) || echo "Too many matches to print in full; narrow with --version or a more exact query."
  printf '%s\n' "$matches" | head -n $((max * 10)) | while IFS= read -r f; do
    printf '%s  %s\n' "${f#"$source_dir"/}" "$(title "$f")"
  done
  if (( total > max * 10 )); then echo "... $((total - max * 10)) more"; fi
  exit 0
fi

printf '%s\n' "$matches" | while IFS= read -r f; do
  echo
  echo "===== ${f#"$source_dir"/}"
  # Drop the rST include/anchor/index boilerplate, keep the text.
  grep -vE '^\.\. +(include::|_[A-Za-z0-9_-]+:|index::)|^ *:tags:' "$f" | cat -s || true
done