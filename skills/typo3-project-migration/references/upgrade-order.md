# Order of operations for one hop

Run these in this order for every hop, on the copy, and write down the exact
commands: the runbook for production repeats them. `t3.sh` is
`scripts/t3.sh`. It runs `vendor/bin/typo3` inside DDEV when the project is a
DDEV project.

Everything up to step 5 is revertible with git. Step 5 onward writes the
database.

## 1. Before the hop

- The previous hop's gate is green and committed.
- The deprecation log of the current version has been read (if it was
  enabled). Each entry is a call that the next major may remove.
- The matrix row for this hop has no `none`/`unknown` left without a user decision.

## 2. Environment

- PHP to at least the target's minimum, where the site runs. DDEV:
  `php_version` in `.ddev/config.yaml`, `ddev restart`. Check with
  `ddev exec php -v`.
- Database engine if the target needs it (`version-matrix.md`).
- PHP extensions the target needs: `composer check-platform-reqs` after step 4.
- `composer.json` `config.platform.php`, if set, moves with it.
  Otherwise Composer resolves for a PHP that doesn't run.

## 3. Own extensions

Every own extension and the sitepackage must run on the target before
step 4 can boot. See `own-extensions.md`. Commit each extension's migration
on its own.

## 4. Packages, in one call

```bash
composer require --no-update \
  "typo3/cms-core:^13.4" "typo3/cms-backend:^13.4" … every typo3/cms-* … \
  "georgringer/news:^12.0" … every third-party extension at the matrix version …
composer update -W
```

- Remove packages the target no longer ships (`composer remove`), e.g.
  `typo3/cms-recordlist` on v12 or `typo3/cms-t3editor` on v13.
- A conflict names what still blocks. Read it as such, and don't loosen
  constraints until it resolves.
- `composer validate` and `composer check-platform-reqs` must pass.
- Commit `composer.json` and `composer.lock` together.

## 5. Database (needs a dump of this hop first)

```bash
ddev export-db --file=.project-migration/backups/pre-v13.sql.gz   # or ddev snapshot --name pre-v13
scripts/t3.sh extension:setup        # schema additions, static data, extension setup
scripts/t3.sh upgrade:list           # what is pending, and why
scripts/t3.sh upgrade:run <identifier>   # one by one when a wizard asks a question
scripts/t3.sh upgrade:run            # the rest
scripts/t3.sh upgrade:list           # until: "No wizards available."
scripts/t3.sh upgrade:list --all     # what is marked done; compare with the records
```

- A wizard that refuses usually means a step above was skipped (schema not
  current, reference index stale). Fix that and don't force it.
- `upgrade:run` marks a wizard done without doing anything when its
  `updateNecessary()` returns false. For wizards that migrate data (scheduler
  tasks in v14, file references, plugin `list_type` to `CType`), look at the
  records afterwards.
- Destructive schema changes (renamed or removed fields and tables, which the Install
  Tool's *Analyze Database Structure* lists as "remove"/"drop") wait until the hop is
  verified. They are the user's call, and the guard hook asks before running them.

## 6. Caches, language packs, index

```bash
scripts/t3.sh cache:flush
scripts/t3.sh language:update          # if the site or backend uses translations
scripts/t3.sh referenceindex:update    # after wizards that move relations
```

## 7. Prove

`scripts/project-gate.sh --target <N>` must exit 0. Then this manual
checklist, together with the user:

- [ ] Backend login as admin and as a typical editor (groups, mounts, permissions)
- [ ] Page module, list module, file list, each own backend module
- [ ] Create, edit, translate, hide and delete one record of each important type, including RTE content
- [ ] Forms: submit each frontend form, and check the mail arrives
- [ ] Scheduler: run each task once, `scripts/t3.sh scheduler:run --task=<uid>` or in the module
- [ ] Frontend login, search, and any page the smoke list can't reach
- [ ] Reports module > Status: no errors

Then the **upgrade-reviewer** agent. Then commit and tag the hop.
