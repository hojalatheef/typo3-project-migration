#!/usr/bin/env bash
# smoke-test.sh — capture how the frontend answers before an upgrade and
# compare it afterwards. The pages a site serves are the project's real test
# suite; this makes "it still works" a diff instead of an impression.
#
# Usage:
#   smoke-test.sh seed [--base URL] [--max N]   write .project-migration/urls.txt
#   smoke-test.sh capture <label>               write .project-migration/smoke/<label>.tsv
#   smoke-test.sh compare <before> <after> [N]  report regressions: exit 1 if any,
#                                               exit 3 if none but pages are broken in both
#
# seed reads every site's base (and language bases) from config/sites/*/config.yaml,
# resolves relative or %env()% bases against --base (default: the DDEV primary
# URL), then adds up to --max (default 40) URLs from each site's sitemap.xml.
# Edit urls.txt by hand afterwards: add the pages that matter (forms, search,
# news detail, login-protected entry points), one URL per line, # for comments.
#
# capture records per URL: HTTP status, final URL after redirects, body size,
# <title>, and whether the body carries a TYPO3/PHP error marker.
#
# compare flags: status changed, a new error marker, title changed, body size
# changed by more than N percent (default 30). A page that answers 5xx, nothing
# or with an error marker before AND after is reported as BROKEN: it proves
# nothing about the upgrade, so fix it or take it off the list.

set -euo pipefail

state=".project-migration"
urls="$state/urls.txt"
smoke="$state/smoke"
markers='Oops, an error occurred|An exception occurred|Uncaught .*Exception|Fatal error|Whoops, looks like|TYPO3 Exception|Parse error:'

curl_opts=(-sS -k -L --max-redirs 5 --max-time 30 -A "typo3-project-migration smoke test")

die() { echo "smoke-test.sh: $*" >&2; exit 2; }

# Every <loc> of a sitemap, one per line (sitemaps are often a single line).
locs() { command grep -o '<loc>[^<]*</loc>' | sed -e 's:<loc>::' -e 's:</loc>::' -e 's/&amp;/\&/g'; }

ddev_url() {
  [[ -f .ddev/config.yaml ]] && command -v ddev >/dev/null || return 1
  ddev describe -j 2>/dev/null | jq -r '.raw.primary_url // empty'
}

seed() {
  local base="" max=40
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base) base="$2"; shift 2 ;;
      --max) max="$2"; shift 2 ;;
      *) die "unknown seed argument $1" ;;
    esac
  done
  [[ -n "$base" ]] || base="$(ddev_url || true)"
  base="${base%/}"
  mkdir -p "$state"
  local tmp; tmp="$(mktemp)"
  local cfg b
  for cfg in config/sites/*/config.yaml typo3conf/sites/*/config.yaml; do
    [[ -f "$cfg" ]] || continue
    # base: at top level and inside languages:
    while IFS= read -r b; do
      b="$(printf '%s' "$b" | tr -d "'\"" | sed 's/[[:space:]]*$//')"
      [[ -z "$b" ]] && continue
      if [[ "$b" == %env* || "$b" != http* ]]; then
        [[ -n "$base" ]] || { echo "skip (unresolved base '$b' in $cfg; pass --base)" >&2; continue; }
        [[ "$b" == %env* ]] && b="/"
        b="$base/${b#/}"
      fi
      echo "$b" >> "$tmp"
    done < <(sed -n 's/^[[:space:]]*base:[[:space:]]*//p' "$cfg")
  done
  [[ -s "$tmp" ]] || { [[ -n "$base" ]] && echo "$base/" >> "$tmp"; }
  [[ -s "$tmp" ]] || die "no site base found; pass --base https://your-site.example"

  local site sm loc n
  sort -u "$tmp" -o "$tmp"
  while IFS= read -r site; do
    n=0
    sm="$(curl "${curl_opts[@]}" "${site%/}/sitemap.xml" 2>/dev/null || true)"
    # One level of sitemap index.
    if printf '%s' "$sm" | command grep -q '<sitemapindex'; then
      sm="$(locs <<<"$sm" | head -5 \
        | while IFS= read -r loc; do curl "${curl_opts[@]}" "$loc" 2>/dev/null || true; done)"
    fi
    while IFS= read -r loc; do
      [[ -z "$loc" ]] && continue
      echo "$loc" >> "$tmp"; n=$((n+1)); [[ $n -ge $max ]] && break
    done < <(locs <<<"$sm")
  done < <(sort -u "$tmp")

  {
    echo "# URLs for smoke-test.sh, generated $(date -u +%Y-%m-%dT%H:%MZ). Edit freely: one URL per line."
    awk '!seen[$0]++' "$tmp"
  } > "$urls"
  rm -f "$tmp"
  echo "wrote $(command grep -vc '^#' "$urls") URL(s) to $urls"
}

capture() {
  local label="${1:-}"
  [[ -n "$label" ]] || die "capture needs a label, e.g. baseline-v11"
  [[ -f "$urls" ]] || die "no $urls; run: smoke-test.sh seed"
  mkdir -p "$smoke"
  local out="$smoke/$label.tsv" body meta status final size title err url
  body="$(mktemp)"
  printf 'url\tstatus\tfinal\tbytes\ttitle\terror\n' > "$out"
  while IFS= read -r url; do
    [[ -z "$url" || "$url" == \#* ]] && continue
    meta="$(curl "${curl_opts[@]}" -o "$body" -w '%{http_code}\t%{url_effective}\t%{size_download}' "$url" 2>/dev/null || printf '000\t-\t0')"
    status="$(cut -f1 <<<"$meta")"; final="$(cut -f2 <<<"$meta")"; size="$(cut -f3 <<<"$meta")"
    title="$(tr '\n\t' '  ' < "$body" | sed -n 's:.*<title[^>]*>\([^<]*\)</title>.*:\1:p' | sed 's/^ *//;s/ *$//' | cut -c1-120)"
    err=no; command grep -Eq "$markers" "$body" 2>/dev/null && err=yes
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$url" "$status" "${final#*://*/}" "$size" "$title" "$err" >> "$out"
    printf '  %s %s %s\n' "$status" "$([[ $err == yes ]] && echo 'ERROR-MARKER' || echo '')" "$url"
  done < "$urls"
  rm -f "$body"
  echo "captured $(($(wc -l < "$out") - 1)) URL(s) to $out"
  local broken
  broken="$(awk -F'\t' 'NR>1 && ($2 ~ /^(000|5)/ || $6 == "yes")' "$out" | wc -l | tr -d ' ')"
  [[ "$broken" == 0 ]] || echo "WARNING: $broken URL(s) answer 5xx, nothing, or with an error marker in this capture. Fix them or remove them from $urls before relying on it as a baseline."
}

compare() {
  local before="$smoke/${1:-}.tsv" after="$smoke/${2:-}.tsv" tol="${3:-30}"
  [[ -f "$before" && -f "$after" ]] || die "compare needs two captured labels (have: $(ls "$smoke" 2>/dev/null | sed 's/\.tsv$//' | tr '\n' ' '))"
  awk -F'\t' -v tol="$tol" '
    NR==FNR { if (FNR>1) { s[$1]=$2; t[$1]=$5; b[$1]=$4; e[$1]=$6 } next }
    FNR==1 { next }
    {
      u=$1; total++
      if (!(u in s)) { printf "NEW      %s (%s)\n", u, $2; next }
      was_broken = (s[u] ~ /^(000|5)/ || e[u] == "yes"); is_broken = ($2 ~ /^(000|5)/ || $6 == "yes")
      if (was_broken && is_broken) { printf "BROKEN   %s: status %s before and %s after\n", u, s[u], $2; brk++; next }
      bad=""
      if (s[u] != $2) bad=bad sprintf(" status %s→%s", s[u], $2)
      if (e[u]=="no" && $6=="yes") bad=bad " error-marker"
      if (t[u] != $5) bad=bad sprintf(" title \"%s\"→\"%s\"", t[u], $5)
      if (b[u] > 0) { d=($4-b[u])*100/b[u]; if (d<0) d=-d; if (d>tol) bad=bad sprintf(" size %d→%d", b[u], $4) }
      if (bad != "") { printf "REGRESS  %s:%s\n", u, bad; reg++ } else ok++
    }
    END {
      printf "\n%d URL(s): %d unchanged, %d regressed, %d broken before and after\n", total, ok, reg, brk
      exit (reg > 0 ? 1 : (brk > 0 ? 3 : 0))
    }' "$before" "$after"
}

cmd="${1:-}"; [[ $# -gt 0 ]] && shift
case "$cmd" in
  seed) seed "$@" ;;
  capture) capture "$@" ;;
  compare) compare "$@" ;;
  -h|--help|"") sed -n '2,24p' "$0" ;;
  *) die "unknown command $cmd" ;;
esac
