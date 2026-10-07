# Troubleshooting a project upgrade

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| `composer update` reports a conflict on `typo3/cms-core` | a third-party extension has no release for the target, or the root still pins an old `typo3/cms-*` | read the conflict for the package name. Check its row in `matrix.md`. Bump every `typo3/cms-*` together |
| `Your requirements could not be resolved … php` | Composer resolves for a PHP older than the target needs (`config.platform.php`, or host PHP outside DDEV) | raise `php_version` in DDEV and `config.platform.php`, run `ddev composer` |
| Blank page or "Oops, an error occurred!" | an exception in the frontend | `var/log/typo3_*.log` (classic mode: `typo3temp/var/log/`). The exception code is searchable in the changelog |
| 404 for CSS/JS/images after v12 | extension assets moved to `public/_assets/<hash>/` and something still points to `typo3conf/ext/` | `EXT:` paths in TypoScript and Fluid, web server rules for `_assets`, build output paths |
| Backend module missing for editors | module renamed, merged or newly registered, so the group's module rights don't include it | edit `be_groups` module access, and compare with an admin view |
| A wizard doesn't run or keeps reappearing | prerequisite missing (schema not current, reference index) or data it can't migrate | `extension:setup` first, `referenceindex:update`, then read the wizard's changelog entry (v14 scheduler: Important-106532) |
| Wizard list empty but data not migrated | `upgrade:run` marked the wizard done because `updateNecessary()` returned false | `upgrade:list --all`, inspect the records, `upgrade:mark:undone <id>` (v13.3+) and rerun |
| `Class … not found` from scheduler | a task's class was renamed or removed in an upgraded extension | recreate the task. On v14, check the serialized-task wizard |
| RTE strips markup after saving (v12) | CKEditor 5 only keeps what the preset allows | extend the preset's allowed tags and classes, and compare old and new content of a few records |
| `Unknown column …` after a hop | schema not updated | `extension:setup`, then the Install Tool's *Analyze Database Structure* for what remains |
| Install Tool locked | `ENABLE_INSTALL_TOOL` file missing | create `var/transient/ENABLE_INSTALL_TOOL` (Composer mode) or `typo3conf/ENABLE_INSTALL_TOOL` |
| Dev Companion tools missing after install | session started before `.mcp.json` existed, or the server isn't approved | restart Claude Code, approve in `/mcp`. A refused server is reset with `claude mcp reset-project-choices` |
