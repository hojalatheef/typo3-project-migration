# Project areas to check on every hop

An extension migration looks at `Classes/` and `Configuration/`. A project
migration also owns everything around them. Give each area to one
**project-scout** agent on large projects. Each returns findings with
file:line, and the hop card says what to look for.

| Area | Where | Typical findings |
| --- | --- | --- |
| System configuration | `config/system/settings.php`, `additional.php` (v12+), `typo3conf/LocalConfiguration.php`, `AdditionalConfiguration.php` (≤ v11), `.env` | options the target removed (search each `TYPO3_CONF_VARS` key in the changelog: `typo3_changelog_lookup` or `scripts/changelog-lookup.sh`), environment switches, hard-coded paths |
| Site configuration | `config/sites/*/config.yaml`, `settings.yaml`, `csp.yaml` | language definitions, route enhancers, `base` variants per context, `dependencies:` (sets, v13+), error handling pages |
| Sitepackage TypoScript and TSconfig | the own sitepackage's `Configuration/TypoScript`, `Configuration/TsConfig`, `page.tsconfig`, `sys_template` records | removed options from the hop card, `userFunc` targets, conditions, `@import` paths, `typo3conf/ext/` paths |
| `sys_template` and `pages.TSconfig` in the database | read them with the backend's TypoScript module, or a scout querying through `t3.sh` | TypoScript living in records doesn't show up in grep. Export it once per hop and diff it |
| RTE | `Configuration/RTE/*.yaml` in the sitepackage, `RTE.default.preset` in TSconfig | CKEditor 4 → 5 (v12), allowed tags and classes, custom plugins |
| Templates | Fluid templates, layouts and partials of the sitepackage, overrides of third-party templates (`templateRootPaths`) | third-party template overrides drift from the new extension version. Diff each override against the new original |
| Forms | `fileadmin/form_definitions/*.form.yaml`, form setup YAML, custom finishers | removed templates and finishers per hop card. Re-submit every form |
| Web server | `public/.htaccess`, nginx/Apache vhosts, CDN rules | `_assets/` (v12), `typo3conf/ext/` URLs, compression moved out of TYPO3 (v14), updated default `.htaccess` |
| Scheduler | scheduler tasks, cron entries | task classes that changed or vanished, serialized tasks (v14 wizard), command names |
| Backend users and permissions | `be_groups`: module access, mounts, table and field permissions | renamed or merged modules (e.g. Access → Permissions in v13). Editors lose access silently |
| Deployment and CI | `deploy.php`, Surf, GitLab/GitHub workflows, Dockerfiles, `.ddev/` | PHP version, `PackageStates.php`, `config/system/` paths, steps such as `extension:setup`, `upgrade:run`, `cache:flush` |
| Build pipeline | `package.json`, webpack/vite configs | output paths under `typo3conf/ext/` (v12). Asset compression and concatenation now belong here (v14) |
| Third-party template and TypoScript overrides | `plugin.tx_news`, `plugin.tx_powermail` etc. in the sitepackage | each upgraded extension's own breaking changes. The **extension-auditor** report for that package lists them |
