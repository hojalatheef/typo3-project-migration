---
type: llm
weight: 2
---

PASS if the answer treats this as two hops (12.4 → 13.4, then 13.4 → 14.3) and names at least four of: acme/legacy-slider as a blocker that can't be checked on Packagist (private repository), the MariaDB 10.3 in DDEV being below what v13 needs (10.4.3+), PHP 8.1 having to rise to 8.2, `typo3/cms-t3editor` to remove on v13, `typo3/cms-setup` to remove on v14.3, the sitepackage's `userFunc` needing `#[AsAllowedCallable]` on v14, the `getTSFE()` TypoScript condition removed in v14, the `typo3conf/ext/` CSS path, `additionalAbsRefPrefixDirectories`/`absRefPrefix` behaviour change in v14. It must give an effort rating.
FAIL if it suggests jumping from 12 to 14 in one step, invents changelog entries, or modifies files.
