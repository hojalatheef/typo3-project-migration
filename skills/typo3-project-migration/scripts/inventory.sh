#!/usr/bin/env bash
# inventory.sh — facts about a TYPO3 project (an installation, not one extension)
# before anything is upgraded.
#
# Usage: inventory.sh [project-dir] [--json]
#
# Reports: Composer or classic mode, the installed core version, the declared
# typo3/cms-* and PHP constraints, every extension split into own (path
# repositories, packages/, local typo3conf/ext) and third-party, the system
# configuration files, the sites and whether they use site sets, the runtime
# environment (DDEV, host PHP) and deployment files. Reads files only: no
# database, no console, no network. Exit 0, or 2 if the directory has no
# TYPO3 project in it.

set -euo pipefail

dir="."
json=0
for a in "$@"; do
  case "$a" in
    --json) json=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) dir="$a" ;;
  esac
done
cd "$dir" || exit 2
command -v jq >/dev/null || { echo "inventory.sh needs jq" >&2; exit 2; }

# ---------------------------------------------------------------- mode
mode="unknown"
if [[ -f composer.json ]] && jq -e '(.require // {}) | keys[] | select(startswith("typo3/cms-"))' composer.json >/dev/null 2>&1; then
  mode="composer"
elif [[ -d typo3conf || -e typo3_src || -d typo3/sysext ]]; then
  mode="classic"
fi
[[ "$mode" == unknown ]] && { echo "no TYPO3 project found in $(pwd) (no composer.json requiring typo3/cms-*, no typo3conf/, no typo3_src)" >&2; exit 2; }

web_dir="public"
vendor_dir="vendor"
if [[ -f composer.json ]]; then
  web_dir="$(jq -r '.extra["typo3/cms"]["web-dir"] // "public"' composer.json)"
  vendor_dir="$(jq -r '.config["vendor-dir"] // "vendor"' composer.json)"
fi
[[ "$mode" == classic ]] && web_dir="."

# ---------------------------------------------------------------- core version
core_version=""
for f in "$vendor_dir/typo3/cms-core/Classes/Information/Typo3Version.php" \
         typo3_src/typo3/sysext/core/Classes/Information/Typo3Version.php \
         typo3/sysext/core/Classes/Information/Typo3Version.php \
         "$web_dir/typo3/sysext/core/Classes/Information/Typo3Version.php"; do
  if [[ -f "$f" ]]; then
    core_version="$(sed -n "s/.*const VERSION = '\([^']*\)'.*/\1/p" "$f" | head -1)"
    break
  fi
done
if [[ -z "$core_version" && -f composer.lock ]]; then
  # typo3/cms is the monolithic package of TYPO3 7 and older.
  core_version="$(jq -r '.packages[] | select(.name=="typo3/cms-core" or .name=="typo3/cms") | .version' composer.lock | sed 's/^v//' | head -1)"
  [[ -n "$core_version" ]] && core_version="$core_version (from composer.lock, not installed)"
fi
if [[ -z "$core_version" && -L typo3_src ]]; then
  core_version="$(readlink typo3_src | sed -n 's/.*typo3_src-\([0-9][0-9.]*\).*/\1/p')"
fi
core_major="$(printf '%s' "$core_version" | sed -n 's/^\([0-9][0-9]*\)\..*/\1/p')"

# ---------------------------------------------------------------- constraints
core_constraint=""; php_constraint=""; cms_packages="[]"; installers=""
if [[ -f composer.json ]]; then
  core_constraint="$(jq -r '.require["typo3/cms-core"] // ""' composer.json)"
  php_constraint="$(jq -r '.require.php // .config.platform.php // ""' composer.json)"
  cms_packages="$(jq -c '[(.require // {}) | to_entries[] | select(.key|startswith("typo3/cms-")) | {name:.key, constraint:.value}]' composer.json)"
fi
if [[ -f composer.lock ]]; then
  installers="$(jq -r '[.packages[], (.["packages-dev"] // [])[]] | map(select(.name=="typo3/cms-composer-installers")) | .[0].version // ""' composer.lock)"
fi
mixed_cms="$(jq -r '[.[].constraint] | unique | length' <<<"$cms_packages")"

# ---------------------------------------------------------------- extensions
own="[]"; third="[]"
if [[ -f composer.lock ]]; then
  # A path-repository package is the project's own code; everything else is a dependency.
  own="$(jq -c '[.packages[] | select((.type // "")|startswith("typo3-cms-")) | select(.name|startswith("typo3/cms-")|not)
          | select((.dist.type // "")=="path") | {name, version, key:(.extra["typo3/cms"]["extension-key"] // ""), path:(.dist.url // "")}]' composer.lock)"
  third="$(jq -c '[.packages[] | select((.type // "")|startswith("typo3-cms-")) | select(.name|startswith("typo3/cms-")|not)
          | select((.dist.type // "")!="path") | {name, version, key:(.extra["typo3/cms"]["extension-key"] // "")}]' composer.lock)"
fi
# Extensions that sit in typo3conf/ext without Composer: own code or TER downloads.
# Composer installers up to v3 also put Composer packages there, as real
# directories, so every key composer.lock knows is skipped.
locked_keys=" "
if [[ -f composer.lock ]]; then
  locked_keys=" $(jq -r '[.packages[], (.["packages-dev"] // [])[]] | map(.extra["typo3/cms"]["extension-key"] // empty, (.name | split("/")[1] | gsub("-";"_"))) | join(" ")' composer.lock) "
fi
local_ext="[]"
for ext_root in "$web_dir/typo3conf/ext" typo3conf/ext; do
  [[ -d "$ext_root" ]] || continue
  for e in "$ext_root"/*/; do
    [[ -d "$e" ]] || continue
    [[ -L "${e%/}" ]] && continue   # Composer v3/v4 installers symlink into typo3conf/ext
    key="$(basename "$e")"
    [[ "$locked_keys" == *" $key "* ]] && continue
    ver=""
    [[ -f "$e/ext_emconf.php" ]] && ver="$(sed -n "s/.*'version' *=> *'\([^']*\)'.*/\1/p" "$e/ext_emconf.php" | head -1)"
    has_cj=false; [[ -f "$e/composer.json" ]] && has_cj=true
    in_git=false; git ls-files --error-unmatch "$e" >/dev/null 2>&1 && in_git=true
    local_ext="$(jq -c --arg k "$key" --arg v "$ver" --argjson c "$has_cj" --argjson g "$in_git" --arg p "${e%/}" \
      '. + [{key:$k, version:$v, path:$p, composer_json:$c, in_git:$g}]' <<<"$local_ext")"
  done
  break
done

# ---------------------------------------------------------------- configuration and sites
config_files="[]"
for f in config/system/settings.php config/system/additional.php typo3conf/system/settings.php typo3conf/system/additional.php \
         typo3conf/LocalConfiguration.php typo3conf/AdditionalConfiguration.php "$web_dir/typo3conf/LocalConfiguration.php" \
         "$web_dir/typo3conf/AdditionalConfiguration.php" typo3conf/PackageStates.php "$web_dir/typo3conf/PackageStates.php" .env; do
  [[ -f "$f" ]] && config_files="$(jq -c --arg f "$f" '. + [$f]' <<<"$config_files")"
done
sites="[]"
for sd in config/sites typo3conf/sites; do
  [[ -d "$sd" ]] || continue
  for c in "$sd"/*/config.yaml; do
    [[ -f "$c" ]] || continue
    id="$(basename "$(dirname "$c")")"
    base="$(sed -n 's/^base: *//p' "$c" | head -1 | tr -d "'\"")"
    sets=false; command grep -q '^dependencies:' "$c" && sets=true
    sites="$(jq -c --arg i "$id" --arg b "$base" --argjson s "$sets" '. + [{identifier:$i, base:$b, site_sets:$s}]' <<<"$sites")"
  done
done
ts_files="$(find . \( -path ./vendor -o -path "./$vendor_dir" -o -path ./node_modules -o -path ./var -o -path ./.git \) -prune -o \
  \( -name '*.typoscript' -o -name '*.tsconfig' -o -name 'setup.txt' -o -name 'constants.txt' \) -print 2>/dev/null | wc -l | tr -d ' ')"
rte_yaml="$(find . \( -path ./vendor -o -path "./$vendor_dir" -o -path ./node_modules -o -path ./.git \) -prune -o -path '*RTE*' -name '*.yaml' -print 2>/dev/null | wc -l | tr -d ' ')"

# ---------------------------------------------------------------- environment and deployment
ddev=false; ddev_php=""; ddev_db=""
if [[ -f .ddev/config.yaml ]]; then
  ddev=true
  ddev_php="$(sed -n 's/^php_version: *//p' .ddev/config.yaml | tr -d "'\"" | head -1)"
  # Only the keys indented under "database:" count (composer_version, nodejs_version are top-level).
  ddev_db="$(awk '/^[^[:space:]#]/{f=0} /^database:/{f=1;next} f&&/^[[:space:]]+type:/{t=$2} f&&/^[[:space:]]+version:/{v=$2} END{gsub(/["'\'']/,"",t);gsub(/["'\'']/,"",v); if(t!="")print t" "v}' .ddev/config.yaml)"
fi
host_php="$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)"
deploy="[]"
for f in deploy.php deploy.yaml .gitlab-ci.yml .github/workflows bitbucket-pipelines.yml Dockerfile docker-compose.yml .surf Build/Surf .platform.app.yaml; do
  [[ -e "$f" ]] && deploy="$(jq -c --arg f "$f" '. + [$f]' <<<"$deploy")"
done
clean=null
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [[ -z "$(git status --porcelain 2>/dev/null)" ]] && clean=true || clean=false
fi

result="$(jq -n \
  --arg root "$(pwd)" --arg mode "$mode" --arg web "$web_dir" --arg vendor "$vendor_dir" \
  --arg core "$core_version" --arg major "$core_major" --arg cc "$core_constraint" --arg pc "$php_constraint" \
  --argjson cms "$cms_packages" --arg mixed "$mixed_cms" --arg inst "$installers" \
  --argjson own "$own" --argjson third "$third" --argjson local "$local_ext" \
  --argjson cfg "$config_files" --argjson sites "$sites" --arg ts "$ts_files" --arg rte "$rte_yaml" \
  --argjson ddev "$ddev" --arg dphp "$ddev_php" --arg ddb "$ddev_db" --arg hphp "$host_php" \
  --argjson deploy "$deploy" --argjson clean "$clean" '{
    root:$root, mode:$mode, web_dir:$web, vendor_dir:$vendor,
    core:{installed:$core, major:($major|tonumber? // null), constraint:$cc, cms_packages:$cms,
          cms_constraints_differ:(($mixed|tonumber) > 1), composer_installers:$inst},
    php:{constraint:$pc, host:$hphp, ddev:$dphp},
    extensions:{own:$own, third_party:$third, local_typo3conf_ext:$local},
    config_files:$cfg, sites:$sites, typoscript_files:($ts|tonumber), rte_yaml_files:($rte|tonumber),
    environment:{ddev:$ddev, ddev_php:$dphp, ddev_database:$ddb},
    deployment_files:$deploy, git_clean:$clean }')"

if (( json )); then printf '%s\n' "$result"; exit 0; fi

jq -r '
  "Project        \(.root)",
  "Mode           \(.mode)   web-dir: \(.web_dir)   vendor-dir: \(.vendor_dir)",
  "Core           installed \(.core.installed // "?")   constraint \(.core.constraint // "-")   composer-installers \(.core.composer_installers // "-")",
  (if .core.cms_constraints_differ then "               WARNING: typo3/cms-* packages carry different constraints" else empty end),
  (if (.core.major // 99) < 10 then "               WARNING: below TYPO3 10.4. This plugin starts at 10.4: reach it first with the official upgrade guides" else empty end),
  "PHP            declared \(.php.constraint // "-")   host \(.php.host // "-")   ddev \(.php.ddev // "-")",
  "Environment    ddev: \(.environment.ddev)  database: \(.environment.ddev_database // "-")",
  "Git            clean: \(if .git_clean == null then "not a repository" else .git_clean end)",
  "",
  "Own extensions (\(.extensions.own|length) via path repositories, \(.extensions.local_typo3conf_ext|length) in typo3conf/ext):",
  (.extensions.own[] | "  own    \(.name) \(.version)  [\(.key)]  \(.path)"),
  (.extensions.local_typo3conf_ext[] | "  local  \(.key) \(.version)  composer.json: \(.composer_json)  in git: \(.in_git)"),
  "Third-party extensions (\(.extensions.third_party|length)):",
  (.extensions.third_party[] | "  \(.name) \(.version)  [\(.key)]"),
  "",
  "Config files   \(.config_files | join(", "))",
  "Sites          \(.sites | map("\(.identifier) (\(.base))\(if .site_sets then " +sets" else "" end)") | join(", "))",
  "TypoScript/TSconfig files: \(.typoscript_files)   RTE YAML files: \(.rte_yaml_files)",
  "Deployment     \(.deployment_files | join(", "))"
' <<<"$result"
