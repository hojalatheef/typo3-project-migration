# Hop v10.4 → v11.5 (project level)

Each line names the core changelog entry. Read it before acting:
`scripts/changelog-lookup.sh <id>`, or `typo3_changelog_lookup` with the id as
query. The Dev Companion's knowledge starts at 12.4, so for this hop the
changelog script is the main source. Extension code changes belong to
`own-extensions.md`, not here.

## Environment

- PHP 7.4 is the overlap of both lines. Move the copy to 7.4 first, prove v10 still runs, then hop.

## Composer and extensions

- Feature-94996 / Important-95647: in Composer mode, every extension installed with Composer is active, and `typo3conf/PackageStates.php` is neither written nor read. Remove it from git and from deployment scripts. Activation is now `composer require` plus `extension:setup`.
- Deprecation-94996: extensions placed in `typo3conf/ext` without Composer are deprecated in Composer mode. Give each one a path repository (`packages/<ext>`) now, because v12 drops them.
- `typo3/cms-core` 11.5 accepts `typo3/cms-composer-installers` `^2.0 || ^3.0 || ^4.0`. `^4` is the opt-in preview of the v12 layout (`vendor/` + `_assets`, Important-98484). Taking it here splits the v12 hop in two smaller ones.

## System and frontend

- Important-91888: EXT:about merged into EXT:backend. Remove `typo3/cms-about` from `composer.json`.
- Breaking-91909: the `sys_collection` tables and API moved to `friendsoftypo3/legacy-collections`. If the project has records in `sys_collection`, require it in the same `composer require`. Otherwise the schema compare offers to drop the tables.
- Deprecation-94165: the `sys_language` table is deprecated. Languages come from the site configuration. Check that every site's `languages:` is complete.
- Breaking-91562: cObject `TEMPLATE` removed. Search the sitepackage TypoScript for `= TEMPLATE` and move to `FLUIDTEMPLATE`.
- Breaking-91563: `TSFE->setJS()`, `additionalJavaScript`, `additionalCSS`, `JSCode` and `inlineJS` removed. These are own-extension code, often old sitepackage hooks. Hand them to `own-extensions.md`.
- Breaking-92352: new default position of the redirect middleware. Re-test redirects from the Redirects module.
- Important-92870: the Fluid-based page module is always used. Custom `mod.web_layout` tweaks and backend layouts need a look.
- Important-94312: `BE/loginSecurityLevel` and `FE/loginSecurityLevel` removed. Delete them from the system configuration (`settings.php` / `LocalConfiguration.php`).
- Breaking-92807 / Breaking-92801: frontend and backend login behaviour changed. Re-test frontend login and logout, and backend login.
