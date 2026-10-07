# Hop v12.4 → v13.4 (project level)

Read each entry before acting (`typo3_changelog_lookup` with `version: "13"`,
or `scripts/changelog-lookup.sh <id>`). Dev Companion: also
`typo3_changelog_lookup` with `type: breaking`, `version: "13"` and the tags
`TypoScript`, `TSconfig` and `Frontend` for the configuration surface.

## Environment

- Breaking-102779 / Breaking-102518: PHP 8.2+, MySQL 8.0.17+ / MariaDB 10.4.3+ / PostgreSQL 10+ / SQLite 3.8.3+. An older MariaDB/MySQL reports "unsupported" and breaks with Doctrine DBAL 4.

## Packages

- Breaking-102440: EXT:t3editor merged into EXT:backend. Remove `typo3/cms-t3editor`.
- Breaking-102935: EXT:extensionmanager is optional in Composer mode now. `typo3/cms-extensionmanager` can be dropped, and `extension:setup` comes from the core.

## Sites and TypoScript

- Feature-103437 (13.1): site sets. A site can declare `dependencies:` on sets (for example `typo3/fluid-styled-content`, `typo3/seo-sitemap`) instead of static includes in `sys_template`. **Optional.** Static includes keep working. Moving is a separate, later decision. Don't do it in the hop.
- Important-103485: `lib.parseFunc` is provided via EXT:frontend. Check sitepackages that define or copy it.
- Breaking-102731: felogin `showForgotPasswordLink` removed.
- Indexed search: Breaking-102900, 102902, 102907, 102921, 102925, 102945, 102985. Search templates and TypoScript need a pass if the site uses it.

## Users and editors

- Breaking-102763: frontend user password recovery hashes are invalidated. Pending "forgot password" mails stop working after the hop.
- Breaking-102023: `security.usePasswordPolicyForFrontendUsers` removed.
- Important-104037: the *Access* module is renamed to *Permissions*. Check editor group module rights.
- Breaking-102499: user TSconfig `overridePageModule` removed. Breaking-102834: items removed from the new content element wizard. Check `mod.wizards.newContentElement` TSconfig.
