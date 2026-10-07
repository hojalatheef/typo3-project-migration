# Version matrix for projects (v10 - v14)

Checked 2026-10 against the core changelog and `typo3/cms-core`'s `composer.json` per branch.
Re-check `https://get.typo3.org/api/v1/major/` for support dates and the
system requirements page of the target version (Dev Companion:
`typo3_documentation_lookup` with `queries: ["system requirements"]` and `targetVersion`).

## Lines

| Major | LTS | PHP (min - max) | Regular support ends | ELTS ends (paid) | Constraint for `typo3/cms-*` |
| --- | --- | --- | --- | --- | --- |
| 10 | 10.4 | 7.2 - 7.4 | 2023-04-30 | 2027-04-30 | `^10.4` |
| 11 | 11.5 | 7.4 - 8.3 | 2024-10-31 | 2028-10-31 | `^11.5` |
| 12 | 12.4 | 8.1 - 8.4 | 2026-04-30 | 2030-04-30 | `^12.4` |
| 13 | 13.4 | 8.2 - 8.5 | 2027-12-31 | 2030-12-31 | `^13.4` |
| 14 | 14.3 | 8.2 - 8.5 | 2029-06-30 | 2032-06-30 | `^14.3` |

As of 2026-10, only 13.4 and 14.3 get free community updates. A project on
10, 11 or 12 runs without security fixes unless it has an ELTS subscription.
That is usually the argument that gets the upgrade budgeted.

Every `typo3/cms-*` package in the root `composer.json` carries the same
constraint. `^14.4`, `^13.5` and `^12.5` don't exist: the LTS is the last minor.

## Database engines

| Major | MySQL | MariaDB | PostgreSQL | SQLite | Source |
| --- | --- | --- | --- | --- | --- |
| 12 | 8.0+ | 10.3+ | 10.0+ | 3.8.3+ | Breaking-96553 (SQL Server support discontinued) |
| 13 | 8.0.17+ | 10.4.3+ | 10.0+ | 3.8.3+ | Breaking-102779, Breaking-102518 |
| 10, 11, 14 | verify | verify | verify | verify | system requirements page of that version |

Raise the database server in the copy before the hop that needs it. In DDEV,
an engine or major change needs `ddev debug migrate-database` (or export,
change, import). A plain version bump in `config.yaml` doesn't convert the
data directory.

## Composer installers

| Core | `typo3/cms-composer-installers` (required by cms-core) | Effect |
| --- | --- | --- |
| 11.5 | `^2.0 \|\| ^3.0 \|\| ^4.0` | v4 is the opt-in preview of the v12 layout |
| 12.4 | `^5.0` | extensions installed into `vendor/`, public resources symlinked to `public/_assets/<hash>/` (Important-98484) |
| 14.3 | `^5.0.2` | same layout |

Don't require the installers package yourself. `typo3/cms-core` pulls the
right one. A project-level pin is a leftover to remove during the hop that
crosses it.

## Console commands by line

| Command | Available from | Before that |
| --- | --- | --- |
| `upgrade:list`, `upgrade:run` | 10.4 | Install Tool > Upgrade Wizard |
| `cache:flush`, `cache:warmup` | 11.4 (Feature-90197, Feature-93436) | Install Tool > Flush cache, or `helhum/typo3-console` |
| `extension:setup` | 11.5 | Install Tool > Analyze Database Structure, or `typo3-console` |
| `upgrade:mark:undone` | 13.3 (Feature-104655) | `sys_registry` edits (don't) |
| `language:update` | 10.4 | |

The database step of a hop always runs on the **target** code, so a v10 → v11
hop already has `extension:setup` and `cache:flush`. Only work on the v10
source (baseline, pre-hop checks) needs the older routes.
