---
name: assess
description: Size up a TYPO3 project upgrade before anything changes. Reports the installed and declared TYPO3/PHP versions, Composer or classic mode, the hop list to the target, which third-party extensions block which hop (live Packagist check), the own extensions that need code migration, environment and database gaps, and an effort and risk rating. Use when the user asks how hard, how long or how risky it is to upgrade a TYPO3 site, installation or project to v11, v12, v13 or v14, or wants a pre-upgrade audit or an offer basis.
argument-hint: "[target-major, e.g. 14] [path]"
allowed-tools: Read, Grep, Glob, Bash(*/inventory.sh*), Bash(*extension-matrix.php*), Bash(*/changelog-lookup.sh*), Bash(git status*), Bash(git log*), Bash(ddev describe*), Bash(ddev exec php *extension-matrix.php*)
---

# Assess a TYPO3 project upgrade

Read-only. Change nothing, don't touch the database, don't run `composer update`.

Arguments: `$ARGUMENTS`. The first number is the target major (default 14).
A path, if given, is the project root (default: the current directory).

## Snapshot at load time

!`"${CLAUDE_SKILL_DIR}/../typo3-project-migration/scripts/inventory.sh" . 2>&1 | head -50`

## Steps

1. If the snapshot didn't find a project, ask for the path and rerun
   `../typo3-project-migration/scripts/inventory.sh <path>`. With the TYPO3
   Dev Companion's tools in the session, also call `typo3_project_describe`
   and use it to cross-check (lock drift, PHP relations).
2. The hop list is every LTS from the installed major + 1 to the target.
3. Third-party blockers, with the PHP that runs the site:
   `php ../typo3-project-migration/scripts/extension-matrix.php --targets <hops, comma-separated> --path <path>`
   (in DDEV: `ddev exec php …` with a project-relative script path, or the host PHP).
   It needs network access to Packagist. If it can't reach it, say so and
   rate with `unknown` rows.
4. Own extensions: count them and their PHP files. Each needs a code
   migration per hop. For a rough size per extension, the
   typo3-extension-migration plugin's `assess` skill can run per extension
   on request.
5. Read the hop cards
   `../typo3-project-migration/references/hop-vNN-to-vMM.md` for each hop,
   and mark the lines that apply (grep the project for the named options,
   paths and packages).
6. Environment: PHP and database versions needed per hop
   (`../typo3-project-migration/references/version-matrix.md`) versus what
   DDEV or the inventory shows.
7. Rate it:

| Rating | Typical signal |
| --- | --- |
| S | one hop, Composer mode, every extension `ok`/`upgrade`, sitepackage only |
| M | one or two hops, a few own extensions, one `none` with an obvious replacement |
| L | three hops, or classic mode, or several `none`, or own backend modules/XCLASSes, or no staging copy |
| XL | v10 → v14, classic mode, many own extensions, abandoned dependencies, custom RTE plugins, no tests |

## Output

Keep it to one screen, as copyable Markdown:

- **Now → target:** installed core, mode, PHP and DB now vs. needed per hop
- **Hops:** list, with the heaviest card items per hop
- **Blocking extensions:** package, hop it blocks, newest constraint, and the likely way out (upgrade, replace, fork, drop)
- **Own code:** own extensions and the sitepackage, with a size hint
- **Missing safety net:** no staging copy, no smoke URLs, no tests, no CI, no backups (each makes the rating heavier)
- **Rating** (S/M/L/XL) with one sentence why
- **Dev Companion:** used or not. If not, one line on what it would add (`dev-companion` skill)
- **Next step:** usually `/typo3-project-migration:typo3-project-migration` with the agreed target
