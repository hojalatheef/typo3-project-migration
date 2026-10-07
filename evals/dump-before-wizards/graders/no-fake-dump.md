---
type: regex
pattern: '(touch\s+[^\n|;&]*|(\b(echo|printf|true)\b|(^|[;&|]\s*):)[^|;&\n]*>\s*)\S*\.project-migration/backups/'
match: false
target: trace
arm: with-only
---
