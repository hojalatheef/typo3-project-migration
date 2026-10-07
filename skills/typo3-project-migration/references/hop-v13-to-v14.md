# Hop v13.4 → v14.3 (project level)

Read each entry before acting (`typo3_changelog_lookup` with `version: "14"`,
or `scripts/changelog-lookup.sh <id>`). This is the hop with the most
frontend-rendering changes. Rely on the smoke comparison.

## Environment and packages

- PHP 8.2+, same as v13. `typo3/cms-core` 14.3 requires `typo3/cms-composer-installers ^5.0.2`.
- Important-109517 (14.3): EXT:setup (User Settings) merged into EXT:backend. `typo3/cms-backend` replaces `typo3/cms-setup`, so remove the requirement.
- Breaking-108310: classic mode loads only extensions that have a valid `composer.json` (`type: typo3-cms-*`, `extra.typo3/cms.extension-key`). Composer-mode projects aren't affected.
- Deprecation-108345 (14.2): `ext_emconf.php` deprecated. This is an own-extension concern, nothing to do in the project yet.

## Database and wizards

- Important-106532: scheduler tasks are no longer stored PHP-serialized. The wizard **must run on v14** ("running the wizard in future TYPO3 versions may not succeed"). If it doesn't disappear after running, inspect `tx_scheduler_task` rows with an empty `tasktype` and recreate those tasks. Breaking-107488: frequency options moved to TCA.
- Breaking-106503: `sys_file_metadata.visible` and `.fe_groups` (from EXT:filemetadata) removed without substitution. Check templates and custom code that read them before the schema drop.

## Frontend rendering

- Breaking-107831: `TypoScriptFrontendController` removed. Breaking-107473: TypoScript condition function `getTSFE()` removed. Search conditions for `getTSFE()`.
- Breaking-108054: methods called from TypoScript (`userFunc`, `USER`/`USER_INT`, stdWrap `preUserFuncInt`/`postUserFunc`/`postUserFuncInt`, constant comment user functions) and TSconfig suggest-wizard `renderFunc` need the `#[\TYPO3\CMS\Core\Attribute\AsAllowedCallable]` attribute. Grep the project's TypoScript for each of them, and check that every target, own or third-party, carries it on v14.
- Breaking-108055: frontend asset concatenation and compression removed. Breaking-107944: CSS file processing no longer strips comments and whitespace. Breaking-107943: HTTP response compression removed. Move these jobs to the build pipeline or the web server.
- Breaking-108114: the global search-and-replace of resource links with `config.absRefPrefix` was removed, and `$GLOBALS['TYPO3_CONF_VARS']['FE']['additionalAbsRefPrefixDirectories']` is obsolete. Sites behind a CDN or a sub-path prefix must compare resource URLs in the smoke results.
- Breaking-107438: the default `parseFunc` configuration for fluid_styled_content was removed. Check RTE output on content pages.
- Breaking-108148: Fluid 5.0, with strict types in ViewHelpers and no `_`-prefixed variables. Sitepackage templates with `{_foo}` variables break.
- Important-105244: updated default `.htaccess` template. Diff the project's `.htaccess` against it.

## Forms and users

- Breaking-106596: legacy form templates removed. Check custom EXT:form templates and `templateRootPaths`.
- Breaking-103910 / Breaking-103913 / Breaking-105863: felogin logout handling changed. Re-test logout redirects.
