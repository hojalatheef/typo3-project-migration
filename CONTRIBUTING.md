# Contributing

- Keep the reference cards factual and short. Every line in a hop card names
  the core changelog entry it comes from (`Breaking-#NNNNN`, `Important-#NNNNN`).
  Read the entry before writing the line. If you're not sure, write "verify"
  rather than guess.
- Version-specific facts belong in the cards and in `version-matrix.md`, not in
  `SKILL.md`. The skill holds the order of operations.
- Scripts must work with the bash 3.2 that ships with macOS and with GNU/BSD
  userlands (no `mapfile`, no `grep -P`, no `sed -i` without a suffix).
  `extension-matrix.php` must stay parseable on PHP 7.4.
- Run `npm test` (self-test and Markdown lint) before opening a pull request.
- Commit messages follow the TYPO3 style: `[FEATURE]`, `[BUGFIX]`, `[TASK]`, `[DOCS]`.
