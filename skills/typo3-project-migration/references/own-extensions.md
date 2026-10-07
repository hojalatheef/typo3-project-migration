# The project's own extensions

Own extensions are the sitepackage, every path-repository package
(`packages/*`), and anything that lives in `typo3conf/ext` without a public
release. Each one has to run on a hop's target before that hop's
`composer update` can boot the site.

## Who does the work

Pick the first one available:

1. **typo3-extension-migration plugin** (same author). Invoke
   `/typo3-extension-migration:typo3-extension-migration` from the extension's
   directory, with the target "add N+1, keep N". It brings Rector and Fractor,
   the legacy API scan and its own agents. For several extensions, run one
   migration per extension in parallel: each is a disjoint file set.
2. **TYPO3 Dev Companion's `typo3-extension-upgrade` skill**, if the Dev
   Companion was installed into this project with `--agent=claude`. It works
   from the changelog, the Extension Scanner and the deprecation annotations
   of the installed core.
3. Neither: do it directly with `typo3_changelog_lookup`, or
   `scripts/changelog-lookup.sh` and TYPO3 Rector
   (`ssch/typo3-rector`, level set `UP_TO_TYPO3_<N>`).

## Why both lines

An own extension should run on the current **and** the next major during
the hop (`"typo3/cms-core": "^12.4 || ^13.4"`). Then step 3 (own extensions)
and step 4 (packages) of `upgrade-order.md` can be committed and tested
separately, and the site keeps booting between them. After the hop, the
lower line can be dropped in the next hop's own-extension step.

## What the project migration still owns

- The extension's `composer.json` constraint matches the project's.
- The extension is a Composer package (a path repository) before v12, and has a `composer.json` before v14 even in classic mode.
- The sitepackage's TypoScript, TSconfig, RTE YAML and templates are checked against the hop card. That's configuration, not API code, and tools such as Rector don't see it. Fractor covers part of it.
- Extensions nobody maintains anymore: ask whether the feature is still used before migrating it. Dropping one is a valid outcome, and the user's decision.
