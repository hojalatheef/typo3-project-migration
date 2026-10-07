# Classic mode (non-Composer) projects

Signs: no `composer.json` requiring `typo3/cms-*`, a `typo3_src` symlink,
extensions installed through the Extension Manager into `typo3conf/ext`.

## Recommendation: switch to Composer first, on the current version

Switching mode and switching major in one step doubles the unknowns. Switch
on the current version, prove it with a smoke comparison, then upgrade:

1. Create `composer.json` requiring the exact current core version (`typo3/cms-core:11.5.x`) and every system extension that `PackageStates.php` marks active.
2. For each extension in `typo3conf/ext`: its Packagist name (TER page or the extension's `composer.json`). Own extensions become path repositories under `packages/`.
3. Move the document root to `public/` (web server config), keep `fileadmin/` and `typo3temp/` data.
4. `composer install`, `extension:setup` (v11+), cache flush, smoke compare against the classic baseline.
5. Commit, deploy that alone, then start the first hop.

## If the project stays classic

- Hops are done by swapping the `typo3_src` symlink to the next LTS source and updating extensions via TER downloads. The database steps are identical.
- `extension-matrix.php` needs a `composer.lock`. Without one, check each extension key with `typo3_ter_lookup` (Dev Companion) or extensions.typo3.org.
- v12: configuration moves to `typo3conf/system/settings.php` and `additional.php` (Breaking-98319).
- v14: every extension needs a valid `composer.json` with `type: typo3-cms-*` and `extra.typo3/cms.extension-key`, or it isn't loaded (Breaking-108310). That includes own and old TER extensions.
