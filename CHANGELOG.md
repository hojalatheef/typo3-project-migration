# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- `inventory.sh`: a git repository with uncommitted changes was reported as "not a repository" in text output.

### Added

- `dev-companion` skill: running the TYPO3 Dev Companion in Docker when the host has no usable PHP 8.2+, and what that setup can't answer.

## [0.1.0] - 2026-10-07

### Added

- `typo3-project-migration` skill: safety, recon, blockers, plan, per-hop runbook (environment → own extensions → one Composer resolution → configuration → database and wizards → caches → prove), rollout runbook and report, one LTS at a time from v10 to v14.
- `assess`, `verify` and `dev-companion` skills.
- Agents: `project-scout` (Haiku), `extension-auditor` (Sonnet), `upgrade-strategist` (Opus), `upgrade-reviewer` (Opus).
- Scripts: `inventory.sh` (project facts, Composer and classic mode), `extension-matrix.php` (third-party extensions vs. each target major on Packagist, PHP 7.4+), `smoke-test.sh` (seed, capture, compare), `project-gate.sh` (per-hop verdict), `t3.sh` (DDEV-aware TYPO3 console), `changelog-lookup.sh` (official core changelog, shares the cache with typo3-extension-migration).
- Reference cards per hop (v10 → v11 … v13 → v14) built from verified core changelog entries, plus version matrix, upgrade order, project areas, own extensions, classic mode, Dev Companion integration and troubleshooting.
- Guard hook: denies database-writing TYPO3 commands without a dump from the last 24 h, asks before destructive schema or database operations, denies `--no-verify` and `--ignore-platform-req(s)`.
- Optional integration with the TYPO3 Dev Companion MCP server (github.com/TYPO3/dev-companion).
