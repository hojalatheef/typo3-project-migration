# Using the TYPO3 Dev Companion in a project migration

The TYPO3 Dev Companion (github.com/TYPO3/dev-companion, TYPO3 Association,
MIT, a 0.x pre-release) is a local MCP server that answers TYPO3 questions
for the version installed in the project, with the source of each answer.
Its knowledge covers **12.4, 13.4, 14.3 and main**. It reads files only, and
writes nothing into the installation.

Tool names may come qualified (`mcp__typo3-dev-companion__typo3_changelog_lookup`).
Search for the qualified form before concluding the server is missing.

## Where each tool fits

| Phase | Tool | Ask it | Without it |
| --- | --- | --- | --- |
| Recon | `typo3_project_describe` | installed core, PHP floor vs. declared vs. running, own extensions, sites and their sets, commands the repository declares, lock drift | `scripts/inventory.sh` |
| Recon | `typo3_server_scope` | covered versions, whether the server is behind its upstream | — |
| Blockers | `typo3_system_extension_lookup` (`targetVersion`) | does the target still ship each `typo3/cms-*` the project requires | changelog search for "merged" |
| Blockers | `typo3_ter_lookup` | TER releases and their TYPO3 constraints for classic-mode or TER-only extensions | extensions.typo3.org |
| Blockers | `typo3_extension_describe` | what an own extension registers (tables, plugins, modules), so the scope of its migration is known | reading `ext_localconf.php` and `Configuration/` |
| Per hop | `typo3_changelog_lookup` (`type: breaking` then `deprecation`, `version: "<N>"`, raise `limit`) | the full list of the target major, read once per hop. Use the tags (`TypoScript`, `TSconfig`, `Frontend`, `Backend`, `ext:form`, …) to pick the project's surface | `scripts/changelog-lookup.sh --version <N>.0 --list <keyword>` |
| Per hop | `typo3_hint_lookup` (`task: "upgrade installation"`, `paths`) | the installation-upgrade order, with the concrete paths touched | `upgrade-order.md` |
| Per hop, after `composer update` | `typo3_configuration_lookup` (`configurationPath`, e.g. `SYS/caching/cacheConfigurations`) | the effective runtime value in the upgraded installation, after every extension had its say, to confirm settings from `settings.php` still land | `t3.sh configuration:show` (v14.2+, Feature-108815) or the Install Tool's configuration view |
| Per hop | `typo3_changelog_lookup` with the option name as query | whether a `TYPO3_CONF_VARS` key in `settings.php` was removed or renamed | `scripts/changelog-lookup.sh <OptionName> --list` |
| Per hop | `typo3_documentation_lookup` (`targetVersion`) | official docs for the target: site sets, CKEditor 5 presets, system requirements | WebFetch on docs.typo3.org |
| Per hop | `typo3_task_guide` | the brief and checks for a concrete task, given the paths | the hop card |
| Commit | `typo3_commit_message_guide` (`workflow: "project"`) | the commit message for the hop | `[TASK] Upgrade project to TYPO3 vN` |

## Coverage gaps to plan around

- **Sources below 12.4.** For v10 and v11, the server's version-bound knowledge doesn't apply. Use the changelog script for those hops, and the Dev Companion from the v11 → v12 hop's target side onward.
- **It describes the core it was started with.** After each hop's `composer update`, the server must be restarted (`/mcp` → reconnect) before its answers are about the new core.
- **PHP 8.2+ to run.** A DDEV project on v10/v11 runs PHP 7.x in the container. Use a standalone checkout of the Dev Companion run by the host PHP. Its installer then writes `php /absolute/path/bin/typo3-dev-companion`, not `ddev exec php …`. See the `dev-companion` skill.
- **Its own skills are extension-scoped.** `typo3-extension-upgrade` covers one package. The project order (environment, all packages in one resolution, database, wizards, caches, rollout) is this plugin's job. Its `typo3-extension-health`, `-testing` and `-documentation` skills are good follow-ups after the migration, not part of it.
- Its skills say "stop if the server isn't there". That rule belongs to its skills. This plugin works without the server, and says so in the report.
