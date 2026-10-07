---
name: verify
description: Prove that one hop of a TYPO3 project upgrade (or the finished upgrade) works, with measured results. Runs the project gate (installed core, composer validate, platform requirements, console boot, cache flush, pending upgrade wizards, frontend smoke comparison against the pre-upgrade baseline, new error-log lines), walks the manual backend checklist with the user, and has the upgrade-reviewer agent review the hop. Use before calling a hop or the upgrade done, before deploying to staging or production, or when the user asks "does the site still work after the update".
argument-hint: "[target-major] [baseline-label]"
---

# Verify a project upgrade hop

A hop is done when all of the following hold, as measured here. If something
wasn't run, the hop isn't done. Report it as a gap.

Arguments: `$ARGUMENTS`. Target major (default: the installed major) and
baseline label (default `baseline`).

## 1. Gate

```bash
"${CLAUDE_SKILL_DIR}/../typo3-project-migration/scripts/project-gate.sh" --target <N> --baseline <label>
```

Quote the summary block verbatim in the report. For each `FAIL`, open the
log the summary names and fix the cause, never the check. For each
`SKIPPED`, say what would close it. A missing baseline can't be recreated
after the hop: the old version is gone, except by restoring the pre-hop
dump and code on a second copy.

Smoke regressions: go through each `REGRESS` line with the user. A changed
title or size can be an intended change (new markup from an upgraded
extension). The user accepts each one by name, and the ledger records it.
A changed status or a new error marker is a bug until shown otherwise.

## 2. Manual checklist

Walk the checklist in `../typo3-project-migration/references/upgrade-order.md`
section 7 with the user, who clicks while you read logs:

```bash
tail -f var/log/typo3_*.log
```

## 3. Review

Dispatch the **upgrade-reviewer** agent with the hop range (`git log` of the
hop), the gate output, `.project-migration/ledger.md` and `plan.md`. Fix
every `blocker`. Each `concern` gets fixed or recorded as a user decision.

## 4. Verdict

One line per check: `PASS`, `FAIL` or `GAP` with a reason, then
`HOP vN: DONE` only if there is no `FAIL` and no unaccepted `GAP`.
