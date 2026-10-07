#!/usr/bin/env bash
# selftest.sh — structural and behavioural checks for this plugin repository.
# Run from anywhere; exits non-zero if any category fails.
#
# PHP checks use the first working interpreter of: $PHP_BIN, php, a php:8.4-cli
# Docker image. Without any of them they are skipped (and say so).

set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 2
skill="skills/typo3-project-migration"
scripts="$skill/scripts"
fixture="evals/fixtures/project_v12"
fail=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
skip() { printf '  skip  %s\n' "$1"; }

echo "manifests"
for j in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json package.json; do
  jq -e . "$j" >/dev/null 2>&1 && ok "$j is valid JSON" || bad "$j is not valid JSON"
done
v_plugin="$(jq -r .version .claude-plugin/plugin.json)"
grep -q "## \[$v_plugin\]" CHANGELOG.md && ok "CHANGELOG has $v_plugin" || bad "CHANGELOG lacks entry for $v_plugin"
[[ "$(jq -r .version package.json)" == "$v_plugin" ]] && ok "package.json version matches plugin.json" || bad "package.json version differs from plugin.json"

echo "frontmatter"
for f in skills/*/SKILL.md agents/*.md; do
  head -1 "$f" | grep -q '^---$' || { bad "$f: no frontmatter"; continue; }
  fm="$(awk 'NR==1{next} /^---$/{exit} {print}' "$f")"
  grep -q '^description: .\{40,\}' <<<"$fm" || bad "$f: description missing or too short"
  if [[ "$f" == agents/* ]]; then
    grep -Eq '^model: (opus|sonnet|haiku|inherit|claude-)' <<<"$fm" || bad "$f: model missing"
    grep -q '^name: ' <<<"$fm" || bad "$f: name missing"
  fi
done
ok "skills and agents carry frontmatter"

echo "reference links"
for f in skills/*/SKILL.md agents/*.md; do
  base="$skill"; [[ "$f" == skills/* && "$f" != "$skill/SKILL.md" ]] && base="$(dirname "$f")/../typo3-project-migration"
  while IFS= read -r ref; do
    [[ -e "$base/$ref" ]] || bad "$f references missing $ref"
  done < <(grep -Eo '(references|scripts)/[A-Za-z0-9_.-]+\.(md|sh|php)' "$f" | grep -v -e 'vNN' -e 'selftest' | sort -u)
done
for hop in 10-to-v11 11-to-v12 12-to-v13 13-to-v14; do
  [[ -f "$skill/references/hop-v$hop.md" ]] || bad "missing hop card hop-v$hop.md"
done
ok "skill and agent links resolve, every hop has a card"

echo "hop cards cite changelog entries"
uncited=0
for card in "$skill"/references/hop-v*.md; do
  while IFS= read -r line; do
    grep -Eq '(Breaking|Important|Feature|Deprecation)-[0-9]{5,6}|PHP|verify' <<<"$line" || { bad "$(basename "$card"): bullet without a changelog id: ${line:0:70}"; uncited=1; }
  done < <(grep '^- ' "$card")
done
(( uncited )) || ok "every hop-card bullet names its source"

echo "scripts"
if command -v shellcheck >/dev/null; then
  shellcheck -S warning "$scripts"/*.sh hooks/scripts/*.sh scripts/*.sh && ok "shellcheck" || bad "shellcheck"
else skip "shellcheck not installed"; fi
bash -n "$scripts"/*.sh hooks/scripts/*.sh && ok "bash -n"
for s in "$scripts"/*.sh "$scripts"/*.php hooks/scripts/*.sh; do [[ -x "$s" ]] || bad "$s is not executable"; done

echo "php"
php_run=()
if [[ -n "${PHP_BIN:-}" ]] && bash -c '"$0" -r "exit(0);"; exit $?' "$PHP_BIN" >/dev/null 2>&1; then php_run=("$PHP_BIN")
elif bash -c 'php -r "exit(0);"; exit $?' >/dev/null 2>&1; then php_run=(php)
elif command -v docker >/dev/null && docker info >/dev/null 2>&1; then php_run=(docker run --rm -v "$root":"$root" -w "$root" php:8.4-cli php)
fi
if (( ${#php_run[@]} )); then
  "${php_run[@]}" -l "$scripts/extension-matrix.php" >/dev/null && ok "php -l extension-matrix.php" || bad "php -l extension-matrix.php"
  "${php_run[@]}" "$scripts/extension-matrix.php" --selftest >/dev/null && ok "constraint matcher selftest" || bad "constraint matcher selftest"
  out="$("${php_run[@]}" "$scripts/extension-matrix.php" --targets 13,14 --path "$root/$fixture" --packagist-dir "$root/evals/fixtures/packagist" --format json)"; rc=$?
  [[ $rc -eq 1 ]] && ok "matrix exits 1 when something blocks" || bad "matrix exit $rc, expected 1"
  [[ "$(jq -r '.packages[] | select(.package=="georgringer/news") | .majors["13"].version' <<<"$out")" == "12.3.0" ]] \
    && ok "news: newest stable release for v13 is 12.3.0 (beta ignored)" || bad "news v13 resolution wrong"
  [[ "$(jq -r '.packages[] | select(.package=="georgringer/news") | .majors["14"].status' <<<"$out")" == "none" ]] \
    && ok "news: no stable release for v14 in the fixture" || bad "news v14 should be none"
  [[ "$(jq -r '.packages[] | select(.package=="acme/legacy-slider") | .majors["13"].status' <<<"$out")" == "unknown" ]] \
    && ok "private package is unknown" || bad "private package should be unknown"
  [[ "$(jq -r '[.packages[].package] | index("acme/sitepackage")' <<<"$out")" == "null" ]] \
    && ok "own path package is not in the matrix" || bad "own path package leaked into the matrix"
else skip "no working PHP (set PHP_BIN or start Docker)"; fi

echo "inventory on fixture"
inv="$("$scripts/inventory.sh" "$fixture" --json)"
[[ "$(jq -r .mode <<<"$inv")" == composer ]] && ok "mode composer" || bad "mode"
[[ "$(jq -r .core.major <<<"$inv")" == 12 ]] && ok "installed major 12" || bad "installed major"
[[ "$(jq -r '.extensions.own | length' <<<"$inv")" == 1 ]] && ok "one own extension" || bad "own extensions"
[[ "$(jq -r '.extensions.third_party | length' <<<"$inv")" == 2 ]] && ok "two third-party extensions" || bad "third-party extensions"
[[ "$(jq -r .environment.ddev_database <<<"$inv")" == "mariadb 10.3" ]] && ok "DDEV database read" || bad "DDEV database"
"$scripts/inventory.sh" "$(mktemp -d)" >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "no project exits 2" || bad "no project should exit 2"

echo "t3.sh"
( cd "$fixture" && "$root/$scripts/t3.sh" --print list >/dev/null 2>&1 ); [[ $? -eq 2 ]] && ok "no console binary exits 2" || bad "t3.sh without binary should exit 2"
tmp="$(mktemp -d)"; mkdir -p "$tmp/vendor/bin"; touch "$tmp/vendor/bin/typo3"; echo '{}' > "$tmp/composer.json"
[[ "$(cd "$tmp" && "$root/$scripts/t3.sh" --print cache:flush)" == "php vendor/bin/typo3 cache:flush " ]] && ok "runs vendor/bin/typo3 outside DDEV" || bad "t3.sh command line"
rm -rf "$tmp"

echo "smoke compare"
tmp="$(mktemp -d)"; mkdir -p "$tmp/.project-migration/smoke"
printf 'url\tstatus\tfinal\tbytes\ttitle\terror\nhttps://a/\t200\t/\t1000\tHome\tno\nhttps://a/x\t200\tx\t1000\tX\tno\n' > "$tmp/.project-migration/smoke/before.tsv"
printf 'url\tstatus\tfinal\tbytes\ttitle\terror\nhttps://a/\t200\t/\t1100\tHome\tno\nhttps://a/x\t500\tx\t300\tOops\tyes\n' > "$tmp/.project-migration/smoke/after.tsv"
out="$(cd "$tmp" && "$root/$scripts/smoke-test.sh" compare before after)"; rc=$?
[[ $rc -eq 1 ]] && grep -q 'REGRESS  https://a/x: status 200→500 error-marker' <<<"$out" && ok "flags status change and error marker" || bad "smoke compare: $out"
grep -q 'https://a/: ' <<<"$out" && bad "10% size change should be tolerated" || ok "tolerates small size change"
printf 'url\tstatus\tfinal\tbytes\ttitle\terror\nhttps://a/\t500\t/\t100\tOops\tyes\n' > "$tmp/.project-migration/smoke/b2.tsv"
cp "$tmp/.project-migration/smoke/b2.tsv" "$tmp/.project-migration/smoke/a2.tsv"
out="$(cd "$tmp" && "$root/$scripts/smoke-test.sh" compare b2 a2)"; rc=$?
[[ $rc -eq 3 ]] && grep -q '^BROKEN' <<<"$out" && ok "a page broken before and after is BROKEN, exit 3" || bad "broken-in-both: rc $rc"
rm -rf "$tmp"

echo "changelog lookup"
lookup="$scripts/changelog-lookup.sh"
"$lookup" >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "no query exits 2" || bad "no query should exit 2"
tmp="$(mktemp -d)"
cl="$tmp/vendor/typo3/cms-core/Documentation/Changelog/14.0"
mkdir -p "$cl"
printf 'Important: #106532 - Changed database storage format for Scheduler Tasks\n\nscheduler text\n' > "$cl/Important-106532-ChangedDatabaseStorageFormatForSchedulerTasks.rst"
XDG_CACHE_HOME="$tmp/cache" HOME="$tmp" "$lookup" 106532 --path "$tmp" --no-fetch | grep -q 'scheduler text' \
  && ok "finds an issue number in the project's vendor core" || bad "vendor lookup failed"
XDG_CACHE_HOME="$tmp/cache" HOME="$tmp" "$lookup" 11111 --path "$tmp" --no-fetch >/dev/null 2>&1; [[ $? -eq 1 ]] \
  && ok "unknown id exits 1" || bad "unknown id should exit 1"
rm -rf "$tmp"

echo "guard hook"
work="$(mktemp -d)"
probe() {
  local out
  out="$(jq -n --arg c "$1" --arg d "$work" '{cwd:$d, tool_input:{command:$c}}' | hooks/scripts/guard-bash.sh)"
  [[ -z "$out" ]] && { echo allow; return; }
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out"
}
expect() { [[ "$(probe "$2")" == "$1" ]] && ok "$1: $2" || bad "expected $1: $2"; }
expect deny  'vendor/bin/typo3 upgrade:run'
expect deny  'ddev exec vendor/bin/typo3 extension:setup'
expect deny  'skills/typo3-project-migration/scripts/t3.sh upgrade:run sysTemplateWizard'
expect deny  'composer update -W --ignore-platform-reqs'
expect deny  'git commit -m wip --no-verify'
expect ask   'ddev import-db --file=prod.sql.gz'
expect ask   'vendor/bin/typo3 database:updateschema "*"'
expect ask   'mysql -e "DROP DATABASE db"'
expect allow 'vendor/bin/typo3 upgrade:list'
expect allow 'vendor/bin/typo3 cache:flush'
expect allow 'composer update -W'
expect allow 'git commit -m "fix -n handling"'
mkdir -p "$work/.project-migration/backups" && touch "$work/.project-migration/backups/pre-v13.sql.gz"
expect allow 'vendor/bin/typo3 upgrade:run'
expect ask   'vendor/bin/typo3 database:updateschema "*.remove"'
touch -t 202001010000 "$work/.project-migration/backups/pre-v13.sql.gz"
expect deny  'vendor/bin/typo3 extension:setup'
rm -rf "$work"

echo
(( fail )) && { echo "SELFTEST FAILED"; exit 1; }
echo "SELFTEST PASSED"
