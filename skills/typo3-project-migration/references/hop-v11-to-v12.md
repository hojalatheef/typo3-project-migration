# Hop v11.5 → v12.4 (project level)

Usually the biggest project hop: new file layout, new TypoScript parser,
CKEditor 5. Read each entry before acting (`scripts/changelog-lookup.sh <id>`
or `typo3_changelog_lookup`). Dev Companion lookups work for the target side
of this hop (`targetVersion: "12.4"`).

## Environment

- Breaking-96553: PHP 8.1+, MySQL 8.0+ / MariaDB 10.3+ / PostgreSQL 10+. SQL Server is no longer supported.

## Layout and configuration

- Breaking-98319: `typo3conf/LocalConfiguration.php` becomes `config/system/settings.php` and `AdditionalConfiguration.php` becomes `config/system/additional.php` in Composer mode (classic mode: `typo3conf/system/`). The core moves them on first boot. Update `.gitignore`, deployment scripts, symlinks and environment-specific includes in the same commit.
- Important-98484: `typo3/cms-composer-installers` v5 installs extensions to `vendor/`, and `Resources/Public` is served from `public/_assets/<hash>/`. Search the project for `typo3conf/ext/` in templates, TypoScript, CSS, JS, `.htaccess`, nginx rules, build pipelines and the CDN configuration. Use `EXT:` paths instead.
- Breaking-96982: global extensions removed. Breaking-96988: `allowLocalInstall` removed.
- Deprecation-94996 (announced for removal in v12): in Composer mode, extensions copied into `typo3conf/ext` without Composer stop being picked up. Every own extension needs a Composer package (path repository) before this hop.

## TypoScript and TSconfig

- Breaking-97816 (two entries: the new frontend parser and the syntax changes): run every site's TypoScript through the backend's *TypoScript* module and fix what it flags. The parser is more forgiving in most places, but some rarely used syntax details are gone.
- Breaking-96518: `ext_typoscript_setup.txt` / `ext_typoscript_constants.txt` are no longer included.
- Breaking-97065: the frontend always renders UTF-8. Breaking-97550: `config.disableCharsetHeader` removed. Breaking-97927: `config.doctypeSwitch` removed. Breaking-96517: `TMENU` `collapse` removed.
- Breaking-96831: the HTML sanitizer is enforced during frontend rendering. Compare the smoke results of pages with custom HTML in RTE content.

## Editors and backend

- Breaking-96874 / Feature-96874: CKEditor 5 replaces CKEditor 4. CKEditor 4 plugins don't load. Custom RTE YAML presets (`editor.config`, `externalPlugins`, allowed tags and classes) must be rewritten. Check what editors can still enter and that existing content survives an edit-and-save.
- Breaking-98443: EXT:recordlist merged into EXT:backend. Remove `typo3/cms-recordlist`.
- Breaking-96733 / Breaking-97135: backend module registration changed (an extension concern, but every own module must be checked). Re-check module access rights of editor groups after the hop.
- Breaking-97305: CSRF-like login token. Custom backend or frontend login templates need the token field.
- Breaking-96149: EXT:form's email finisher always uses FluidEmail. Check custom mail templates of forms.
