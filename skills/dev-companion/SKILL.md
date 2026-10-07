---
name: dev-companion
description: Check, explain or set up the TYPO3 Dev Companion (the TYPO3 Association's MCP server with version-bound TYPO3 knowledge, github.com/TYPO3/dev-companion) for use with the TYPO3 project migration. Detects whether its typo3_* tools are in the session, reports coverage and staleness, and with the user's consent installs a standalone checkout and registers it for Claude Code in the project. Use when the user asks about the Dev Companion, wants it installed, or when the migration skill suggests it.
argument-hint: "[check|install|update]"
allowed-tools: Read, Bash(git clone *typo3-dev-companion*), Bash(git -C *typo3-dev-companion* *), Bash(composer install --working-dir=*typo3-dev-companion*), Bash(*/bin/typo3-dev-companion *), Bash(php -v), Bash(php -r *), Bash(command -v *), Bash(ls *), Bash(cat .mcp.json)
---

# TYPO3 Dev Companion

Arguments: `$ARGUMENTS` (default `check`).

What it is and how this plugin uses it: `../typo3-project-migration/references/dev-companion.md`.
In short: it's an optional, read-only MCP server. It makes changelog,
documentation, system-extension and TER answers version-exact for 12.4,
13.4, 14.3 and main. It's a 0.x pre-release, so interfaces can change.

## check

1. Are `typo3_*` tools in this session (also in the qualified form
   `mcp__<server>__typo3_project_describe`)? If yes, call
   `typo3_server_scope` with `sections` limited to coverage and upstream, and
   `typo3_project_describe`. Report: covered versions, the installed core
   it sees, whether the server says it is behind its upstream or older than
   its code (then: `update`, and reconnect in `/mcp`).
2. No tools, but `.mcp.json` has a `typo3-dev-companion` entry: the session
   started before the entry existed, or the server isn't approved. Ask the
   user to restart Claude Code and approve it (or `/mcp`). A refused one is
   reset with `claude mcp reset-project-choices`.
3. Neither: it isn't set up. Explain what it would add (one paragraph) and
   offer `install`.

## install

Needs the user's explicit yes, because it writes into the project:
`.mcp.json` (one server entry), `.claude/skills/typo3-*/` (14 task skills,
which ignore themselves in git), and `.typo3-dev-companion/state.json`.

1. A host PHP ≥ 8.2 with `curl` and `dom`: `php -v`. The server runs on the
   host, not in the project's container. That's deliberate: an old project
   (v10/v11) has PHP 7.x in DDEV, which can't run the server.
2. Checkout location: `${TYPO3_DEV_COMPANION_HOME:-$HOME/.local/share/typo3-dev-companion}`.
   One checkout serves every project on the machine.

   ```bash
   home="${TYPO3_DEV_COMPANION_HOME:-$HOME/.local/share/typo3-dev-companion}"
   [ -d "$home/.git" ] || git clone https://github.com/TYPO3/dev-companion.git "$home"
   composer install --working-dir="$home"
   ```

3. From the project root:

   ```bash
   "$home/bin/typo3-dev-companion" install --agent=claude
   ```

   Because the checkout is outside the project, the entry it writes starts
   `php <absolute path>` on the host, also in DDEV projects.
4. Show the user the `.mcp.json` diff. Then: restart Claude Code, approve
   the server, and run `/typo3-project-migration:dev-companion check`.

### No usable host PHP: run it in Docker

If the host has no working PHP 8.2+, run Composer and the installer in
containers that mount both directories at their host paths. Then point the
entry at the container:

```bash
docker run --rm -v "$home":"$home" -w "$home" composer:2 install --no-interaction
docker run --rm -v "$home":"$home" -v "$PWD":"$PWD" -w "$PWD" php:8.3-cli \
  php "$home/bin/typo3-dev-companion" install --agent=claude
jq --arg h "$home" --arg p "$PWD" '.mcpServers["typo3-dev-companion"] = {type:"stdio", command:"docker",
  args:["run","--rm","-i","-v",($h+":"+$h),"-v",($p+":"+$p),"-w",$p,"php:8.3-cli","php",($h+"/bin/typo3-dev-companion")]}' \
  .mcp.json > .mcp.json.tmp && mv .mcp.json.tmp .mcp.json
```

What this costs: the container has neither `ddev` nor the project's
database, so lookups that boot the installation (`typo3_configuration_lookup`,
and others that answer from the installation) report "installation could
not be booted". File-based and network lookups (`typo3_project_describe`,
changelog, documentation, system extensions, TER) work. The installer's
`update` refuses an entry it didn't write, so after an `update` the `jq`
step runs again. Docker must be running when Claude Code starts.

Don't add `typo3/dev-companion` to the project's `composer.json`. It has no
release on Packagist yet, and its PHP 8.2 floor would fight an old
project's constraints.

## update

```bash
git -C "$home" pull --ff-only && composer install --working-dir="$home"
"$home/bin/typo3-dev-companion" update     # in the project root: republish skills, rewrite the entry
```

Then reconnect the server in `/mcp`. A running server keeps the code it
started with.

## Overlap with this plugin

The Dev Companion publishes its own `typo3-extension-upgrade` skill. For the
project's own extensions it's a valid worker (see
`../typo3-project-migration/references/own-extensions.md`), but the project
order (environment, one Composer resolution, database, wizards, rollout)
stays with `typo3-project-migration`.
