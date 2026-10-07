---
name: typo3-project-migration
description: Upgrade a whole TYPO3 project (an installation with its sites, database, configuration and extensions) from an old LTS line to a newer one anywhere between v10 and v14, one major at a time. Covers environment (PHP, database, DDEV), Composer resolution of core and third-party extensions, the project's own extensions, system configuration, site configuration, TypoScript/TSconfig, RTE, database schema and upgrade wizards, smoke tests against a pre-upgrade baseline, and the rollout runbook for staging and production. Use when the user asks to upgrade, update or migrate a TYPO3 site, installation, instance or project to 11, 12, 13 or 14, or to "bring this TYPO3 website to the latest version". For a single extension's code, use the typo3-extension-migration plugin instead.
---

# TYPO3 project migration

This skill moves one TYPO3 installation from its current LTS line to a target
line and proves each step against how the site behaved before. An extension
migration changes code. A project migration changes code **and a database
that git cannot revert**, so the order of operations is the method:

- **Facts before edits.** The inventory, the extension matrix and the official changelog decide the plan. Memory doesn't.
- **One LTS at a time, booted and migrated.** v11 → v12 → v13, never v11 → v13. Each intermediate LTS must run against the database and finish its upgrade wizards, because later majors drop the wizards of earlier ones (Important-106532 states this for the v14 scheduler wizard).
- **Revertible until the database is touched.** Dump before the first command that writes. The plugin's guard hook enforces it.
- **The site's own pages are the test suite.** Capture a smoke baseline on the old version; every hop is compared against it.
- **Green means measured.** A hop is done when `scripts/project-gate.sh --target <N>` exits 0, and not before.

Paths below are relative to this skill's directory (`${CLAUDE_SKILL_DIR}`).

## Working state

Keep progress in the project under `.project-migration/`. Add `backups/` to
`.gitignore` and never commit a dump. The rest may be committed if the team
wants the record.

| File | Holds |
| --- | --- |
| `inventory.json` | output of `scripts/inventory.sh --json` |
| `matrix.md` | output of `scripts/extension-matrix.php --targets …` |
| `plan.md` | hops, per-hop steps, blockers, decisions, rollout runbook |
| `ledger.md` | one line per finding: `id · area · status (open/fixed/deferred/decision) · note` |
| `urls.txt`, `smoke/*.tsv` | smoke URLs and captures (`baseline`, `gate-vNN-…`) |
| `backups/` | database dumps per hop (`pre-v12.sql.gz`, …) |

A new session reads `ledger.md` and `plan.md` and resumes at the first open line.

## TYPO3 Dev Companion

If the session has the `typo3_*` tools of the TYPO3 Dev Companion MCP server
(their names may be qualified, such as
`mcp__typo3-dev-companion__typo3_project_describe`), use them wherever
`references/dev-companion.md` names one. They answer from the installed
core, the official documentation and the Extension Repository, with sources,
for TYPO3 12.4, 13.4, 14.3 and main. Without them, the plugin's own scripts
and `scripts/changelog-lookup.sh` cover the same steps with less depth. Say
which of the two the run used in the final report. The `dev-companion` skill
of this plugin checks or sets up the server. Offer it once in Phase 1 if the
tools are missing, and don't push it.

After every hop's `composer update`, the server still describes the old core
until it restarts. Ask the user to reconnect it (`/mcp`) before the next lookup.

## Phase 0: Safety

1. Work on a copy: a local or staging environment with a fresh production
   database dump and `fileadmin/`, never on production. If the user has no
   such copy, stop and help them set one up (for DDEV: `ddev import-db`,
   `ddev import-files`).
2. Clean working tree, then a branch such as `upgrade/v13`.
3. `mkdir -p .project-migration/backups` and take the first dump:
   `ddev export-db --file=.project-migration/backups/pre-upgrade.sql.gz`
   or `ddev snapshot --name pre-upgrade` (without DDEV: `mysqldump`/`pg_dump`
   into that folder).

## Phase 1: Recon

1. `scripts/inventory.sh --json > .project-migration/inventory.json` and read it.
   With the Dev Companion, also call `typo3_project_describe` and
   `typo3_server_scope`, and note where the two disagree.
2. Agree with the user on **source, target and the hop list.** Every LTS
   between them is a hop: 10.4 → 11.5 → 12.4 → 13.4 → 14.3. Read
   `references/version-matrix.md` for PHP and database requirements per
   line. Only LTS minors are targets.
3. Classic mode (no Composer) is a decision of its own. Moving to Composer
   first, on the current version, is usually the cheapest path. From v14
   on, classic mode needs a valid `composer.json` in every extension anyway
   (Breaking-108310). See `references/classic-mode.md`.
4. Smoke baseline **on the source version**, before any change:
   `scripts/smoke-test.sh seed`, review and extend `urls.txt` with the user
   (forms, search, news detail, protected pages), then
   `scripts/smoke-test.sh capture baseline`.
5. Optional, recommended for v11+ sources: switch on deprecation logging on
   the copy, click through the site and backend, and keep
   `var/log/typo3_deprecations_*.log`. It lists what the next hop removes,
   in this project's real call paths.

## Phase 2: Blockers

1. `php scripts/extension-matrix.php --targets <all hop majors> > .project-migration/matrix.md`.
   Use the PHP that runs the site (`ddev exec php …` in DDEV). The script
   needs PHP 7.4 or newer and network access to Packagist.
2. For every package marked **none** or **unknown**, dispatch one
   **extension-auditor** agent, in parallel. Each returns: whether a release,
   a fork or a patch exists, what replaces it, and what dropping it costs.
3. For classic-mode or TER-only extensions, use `typo3_ter_lookup` (Dev
   Companion) or the extension's page on extensions.typo3.org.
4. For every `typo3/cms-*` package the project requires, check that the
   target still ships it: `typo3_system_extension_lookup` with
   `targetVersion`, or the changelog (`scripts/changelog-lookup.sh merged --list`).
   For example, `typo3/cms-recordlist` was merged into backend in v12
   (Breaking-98443) and `typo3/cms-t3editor` in v13 (Breaking-102440).
5. List the **own extensions** (inventory: `own` and `local_typo3conf_ext`,
   plus the sitepackage). They have to run on the next major before that hop
   can boot. See `references/own-extensions.md` for how to hand them off.

## Phase 3: Plan

Hand inventory, matrix, auditor reports and smoke URL list to the
**upgrade-strategist** agent. It writes `.project-migration/plan.md` with, per
hop: environment changes, the single `composer require` call, own-extension
work, configuration work (from `references/hop-vNN-to-vMM.md`), expected
wizards, the gate, and the decisions that belong to the user (replace or drop
an extension, a feature with no successor, downtime). It also drafts the
rollout runbook. Show the plan and wait for a go-ahead.

## Phase 4: Hops

Repeat for each hop, following `references/upgrade-order.md` step by step:

1. **Environment.** Raise PHP (and the database server if the target needs
   it) where the site runs, before touching constraints. In DDEV: edit
   `php_version` / `database` in `.ddev/config.yaml`, then `ddev restart`.
2. **Own extensions.** Make them run on the next major, ideally on both the
   current and the next one, so the code boots before and after the
   `composer update`. Delegate as `references/own-extensions.md` describes.
   For many own extensions, dispatch one migration per extension in parallel.
3. **Packages.** One `composer require` call with every `typo3/cms-*` package
   at the new LTS constraint and every third-party extension at the version
   the matrix found, plus `-W`. Read a conflict as the list of what still
   blocks. Never use `--ignore-platform-reqs` (the hook denies it). Remove
   packages the target no longer ships.
4. **Project configuration.** Work through the hop card
   `references/hop-vNN-to-vMM.md` and `references/project-areas.md`:
   system configuration, site configuration and sets, TypoScript and
   TSconfig, RTE presets, web server rules, scheduler tasks, forms,
   deployment and CI. For a large project, dispatch **project-scout** agents
   per area in parallel first. Each returns findings with file:line.
5. **Database.** A fresh dump into `backups/pre-vNN.*`, then with
   `scripts/t3.sh`: `extension:setup` → `upgrade:list` → `upgrade:run`
   (per identifier where a wizard asks a question, and ask the user) →
   `upgrade:list` again until "No wizards available." Destructive schema
   changes (dropping renamed columns and tables) wait until the hop is
   verified, and are the user's call.
6. **Caches and language packs.** `t3.sh cache:flush`, then
   `t3.sh language:update` if the site uses translations.
7. **Prove.** `scripts/project-gate.sh --target <N>`. Then the manual
   backend checklist in `references/upgrade-order.md` with the user. Then
   the **upgrade-reviewer** agent on the hop's diff, gate output and ledger.
8. **Commit** the hop (`[TASK] Upgrade project to TYPO3 v13`) and update the
   ledger. Don't start the next hop with a red gate.

When a card's hint isn't enough, look up the official text: `typo3_changelog_lookup`
(Dev Companion) or `scripts/changelog-lookup.sh <id|issue|keyword>`. Never
fill a gap from memory. A wrong removal list reads exactly like a right one.

## Phase 5: Rollout runbook

The copy proved the sequence. Production must get **the same commands in the
same order**. Write `.project-migration/runbook.md` from the real commands of
Phase 4: maintenance window and editor freeze, production dump, deploy code
(per hop if the server's PHP has to change in between), `extension:setup`,
wizards per hop with that hop's code deployed, cache flush, smoke compare
against a baseline captured on production right before, and the rollback
(restore dump + previous release). Production steps are the user's to run.
This skill prepares them and doesn't execute them.

## Phase 6: Report

Give the user:

- hops done, the constraints and PHP/database versions now required
- the gate result per hop, quoted from the actual runs, and every `SKIPPED`
- replaced, patched or dropped extensions, and each decision with who made it
- ledger items left `deferred`, each with a reason
- what editors will notice (new page module, RTE behaviour, site settings, changed backend permissions)
- whether the Dev Companion was used, and for what

## Model and agent usage

| Agent | Model | Used for |
| --- | --- | --- |
| `project-scout` | haiku | read-only sweep of one project area per hop |
| `extension-auditor` | sonnet | one blocking third-party extension: release, fork, patch or replacement |
| `upgrade-strategist` | opus | hop plan, decisions, rollout runbook draft |
| `upgrade-reviewer` | opus | adversarial review of a finished hop |

Own-extension code goes to the typo3-extension-migration plugin's agents
(`code-migrator` and the others) when that plugin is installed. Run scouts,
auditors and extension migrations in parallel. A small project (a sitepackage
and a handful of public extensions) needs no agents: do the phases directly.

## Rules that are never bent

- Never run anything against production. Never skip an intermediate LTS.
- Never run a database-writing step without a dump from this hop. Never drop schema without the user's yes.
- Never use `--ignore-platform-reqs`, `--no-verify`, or a `composer.json` `replace`/`conflict` hack to get past a blocker. Name the blocker.
- Never mark a wizard as done (Install Tool button, `sys_registry` edit) to empty the list. Run it. "No wizards available." only says nothing is pending. `upgrade:run` marks a wizard done without work when its `updateNecessary()` returned false, so check the records a wizard was meant to migrate.
- Never call a hop done with a failed or skipped smoke comparison unless the user accepted each difference.
