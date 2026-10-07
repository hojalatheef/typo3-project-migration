#!/usr/bin/env php
<?php

/*
 * extension-matrix.php — for every dependency in composer.lock that requires
 * typo3/cms-*, find the newest stable release on Packagist that runs on each
 * target TYPO3 major. The answer is the list of third-party extensions that
 * block a hop, which is what decides whether and when a project can move.
 *
 * Usage: extension-matrix.php --targets 12,13,14 [--path .] [--format md|json]
 *                             [--packagist-dir DIR] [--allow-unstable]
 *        extension-matrix.php --selftest
 *
 *   --targets         majors to check, lowest first (default: 14)
 *   --path            project root holding composer.lock (default: .)
 *   --packagist-dir   read <DIR>/<vendor>/<name>.json instead of the network
 *                     (Packagist p2 format; used by tests)
 *   --allow-unstable  also consider alpha/beta/RC releases
 *
 * Status per package and major:
 *   ok        the locked version already allows that major
 *   upgrade   a newer stable release allows it (that version is shown)
 *   none      no published release allows it: replace, patch, fork or drop
 *   unknown   not on Packagist (private repository, VCS, artifact)
 *
 * Exit: 0 = nothing blocks the highest target, 1 = something is none/unknown,
 * 2 = usage error or no composer.lock.
 */

const LTS_MINOR = [9 => 5, 10 => 4, 11 => 5, 12 => 4, 13 => 4, 14 => 3];

// Runs on PHP 7.4 too, so a v10/v11 project can use the PHP it already has.
if (!function_exists('str_starts_with')) {
    function str_starts_with(string $h, string $n): bool { return strncmp($h, $n, strlen($n)) === 0; }
    function str_ends_with(string $h, string $n): bool { return $n === '' || substr($h, -strlen($n)) === $n; }
    function str_contains(string $h, string $n): bool { return strpos($h, $n) !== false; }
}

function normalizeVersion(string $v): ?array
{
    $v = ltrim(trim($v), 'vV');
    $v = preg_replace('/[-+].*$/', '', $v);
    if (!preg_match('/^\d+(\.\d+){0,3}$/', $v)) {
        return null;
    }
    $parts = array_map('intval', explode('.', $v));
    return array_slice(array_pad($parts, 3, 0), 0, 3);
}

function cmp(array $a, array $b): int
{
    for ($i = 0; $i < 3; $i++) {
        if ($a[$i] !== $b[$i]) {
            return $a[$i] <=> $b[$i];
        }
    }
    return 0;
}

/** True when $version (x.y.z) satisfies one Composer constraint string. */
function satisfies(string $version, string $constraint): bool
{
    $v = normalizeVersion($version);
    if ($v === null) {
        return false;
    }
    $constraint = preg_replace('/@[a-z]+/i', '', trim($constraint));
    foreach (preg_split('/\s*\|\|?\s*/', $constraint) as $or) {
        $or = trim($or);
        if ($or === '') {
            continue;
        }
        if (preg_match('/^(\S+)\s+-\s+(\S+)$/', $or, $m)) {
            $or = '>=' . $m[1] . ' <=' . $m[2];
        }
        $or = preg_replace('/(>=|<=|!=|==|<>|>|<|=|\^|~)\s+/', '$1', $or);
        $ok = true;
        foreach (preg_split('/\s*,\s*|\s+/', $or) as $atom) {
            if ($atom !== '' && !matchAtom($v, $atom)) {
                $ok = false;
                break;
            }
        }
        if ($ok) {
            return true;
        }
    }
    return false;
}

function matchAtom(array $v, string $atom): bool
{
    if ($atom === '*' || $atom === 'x') {
        return true;
    }
    if (!preg_match('/^(\^|~|>=|<=|!=|==|<>|>|<|=)?v?(\d+(?:\.(?:\d+|\*|x))*)(?:\.\*)?(?:-\S*)?$/', $atom, $m)) {
        return false;
    }
    $op = $m[1] ?? '';
    $raw = $m[2];
    $wild = str_contains($raw, '*') || str_contains($raw, 'x') || str_ends_with($atom, '.*');
    $raw = preg_replace('/\.(\*|x)$/', '', $raw);
    $given = count(explode('.', $raw));
    $base = normalizeVersion($raw);
    if ($base === null) {
        return false;
    }
    if ($wild && ($op === '' || $op === '=' || $op === '==')) {
        $upper = $base;
        $upper[$given - 1]++;
        for ($i = $given; $i < 3; $i++) {
            $upper[$i] = 0;
        }
        return cmp($v, $base) >= 0 && cmp($v, $upper) < 0;
    }
    switch ($op) {
        case '^':
            $upper = $base[0] > 0 ? [$base[0] + 1, 0, 0]
                : ($base[1] > 0 || $given < 3 ? [0, $base[1] + 1, 0] : [0, 0, $base[2] + 1]);
            return cmp($v, $base) >= 0 && cmp($v, $upper) < 0;
        case '~':
            $upper = $given >= 3 ? [$base[0], $base[1] + 1, 0] : [$base[0] + 1, 0, 0];
            return cmp($v, $base) >= 0 && cmp($v, $upper) < 0;
        case '>=': return cmp($v, $base) >= 0;
        case '>':  return cmp($v, $base) > 0;
        case '<=': return cmp($v, $base) <= 0;
        case '<':  return cmp($v, $base) < 0;
        case '!=': case '<>': return cmp($v, $base) !== 0;
        default:   return cmp($v, $base) === 0;
    }
}

/** Expand Packagist's minified p2 metadata (each entry inherits from the previous one). */
function expand(array $versions): array
{
    $out = [];
    $prev = null;
    foreach ($versions as $entry) {
        if ($prev === null) {
            $current = $entry;
        } else {
            $current = $prev;
            foreach ($entry as $k => $val) {
                if ($val === '__unset') {
                    unset($current[$k]);
                } else {
                    $current[$k] = $val;
                }
            }
        }
        $out[] = $current;
        $prev = $current;
    }
    return $out;
}

function fetchPackage(string $name, ?string $dir): ?array
{
    if ($dir !== null) {
        $file = rtrim($dir, '/') . '/' . $name . '.json';
        $json = is_file($file) ? file_get_contents($file) : false;
    } else {
        $url = 'https://repo.packagist.org/p2/' . $name . '.json';
        $ctx = stream_context_create(['http' => ['timeout' => 15, 'ignore_errors' => true,
            'header' => "User-Agent: typo3-project-migration (Claude Code plugin)\r\n"]]);
        $json = @file_get_contents($url, false, $ctx);
        if ($json === false && trim((string)shell_exec('command -v curl')) !== '') {
            $json = shell_exec('curl -fsSL --max-time 15 ' . escapeshellarg($url) . ' 2>/dev/null') ?: false;
        }
    }
    if ($json === false || $json === '') {
        return null;
    }
    $data = json_decode($json, true);
    $versions = $data['packages'][$name] ?? null;
    return is_array($versions) && $versions !== [] ? expand($versions) : null;
}

/** The constraint a release puts on the TYPO3 core: cms-core first, else any typo3/cms-* it requires. */
function coreConstraint(array $release): ?string
{
    $req = $release['require'] ?? [];
    if (!is_array($req)) {
        return null;
    }
    if (isset($req['typo3/cms-core'])) {
        return $req['typo3/cms-core'];
    }
    foreach ($req as $pkg => $c) {
        if (str_starts_with($pkg, 'typo3/cms-') && $pkg !== 'typo3/cms-composer-installers') {
            return $c;
        }
    }
    return null;
}

function isStable(string $v): bool
{
    return (bool)preg_match('/^v?\d+(\.\d+)*$/', $v);
}

function selftest(): int
{
    $cases = [
        ['14.3.99', '^14.3', true], ['14.3.99', '^13.4 || ^14.3', true], ['13.4.99', '^12.4', false],
        ['13.4.99', '~13.4.0', true], ['13.9.0', '~13.4', true], ['14.3.99', '~13.4', false], ['14.3.99', '~13.4.0', false],
        ['12.4.99', '>=11.5,<13', true], ['13.4.99', '>= 11.5 < 13.0', false], ['12.4.99', '12.4.*', true],
        ['12.4.99', '11.*', false], ['12.4.99', '11.5.0 - 12.4.99', true], ['13.4.99', '^12.4|^13.4', true],
        ['13.4.99', '^13.4.10@dev', true], ['14.3.99', '*', true], ['14.3.99', 'v14.3.0', false],
        ['0.3.5', '^0.3', true], ['0.4.0', '^0.3', false], ['13.4.99', '>=13.4.0 <14.0.0', true],
    ];
    $fail = 0;
    foreach ($cases as [$v, $c, $want]) {
        $got = satisfies($v, $c);
        if ($got !== $want) {
            $fail++;
            fwrite(STDERR, "FAIL satisfies($v, '$c') = " . var_export($got, true) . "\n");
        }
    }
    $expanded = expand([['version' => '2.0.0', 'require' => ['a' => '1']], ['version' => '1.0.0'], ['version' => '0.9.0', 'require' => '__unset']]);
    if (($expanded[1]['require']['a'] ?? null) !== '1' || isset($expanded[2]['require'])) {
        $fail++;
        fwrite(STDERR, "FAIL expand()\n");
    }
    echo $fail === 0 ? 'selftest: ' . count($cases) . " constraint cases and expand() pass\n" : "selftest: $fail failure(s)\n";
    return $fail === 0 ? 0 : 1;
}

// ---------------------------------------------------------------- main
$opts = getopt('', ['targets:', 'path:', 'format:', 'packagist-dir:', 'allow-unstable', 'selftest', 'help']);
if (isset($opts['help'])) {
    echo implode("\n", array_slice(explode("\n", file_get_contents(__FILE__)), 4, 26)), "\n";
    exit(0);
}
if (isset($opts['selftest'])) {
    exit(selftest());
}
$targets = array_map('intval', explode(',', $opts['targets'] ?? '14'));
sort($targets);
foreach ($targets as $t) {
    if (!isset(LTS_MINOR[$t])) {
        fwrite(STDERR, "unknown TYPO3 major $t (known: " . implode(',', array_keys(LTS_MINOR)) . ")\n");
        exit(2);
    }
}
$path = rtrim($opts['path'] ?? '.', '/');
$format = $opts['format'] ?? 'md';
$pdir = $opts['packagist-dir'] ?? null;
$unstable = isset($opts['allow-unstable']);
$lockFile = $path . '/composer.lock';
if (!is_file($lockFile)) {
    fwrite(STDERR, "no composer.lock in $path — run composer install first (classic-mode projects: check typo3conf/ext keys with typo3_ter_lookup or extensions.typo3.org)\n");
    exit(2);
}
$lock = json_decode(file_get_contents($lockFile), true);
$rows = [];
foreach (array_merge($lock['packages'] ?? [], $lock['packages-dev'] ?? []) as $pkg) {
    $name = $pkg['name'];
    if (str_starts_with($name, 'typo3/cms-') || ($pkg['dist']['type'] ?? '') === 'path') {
        continue; // core packages move with the core; own path packages belong to the extension migration
    }
    $locked = coreConstraint($pkg);
    if ($locked === null) {
        continue;
    }
    $row = ['package' => $name, 'key' => $pkg['extra']['typo3/cms']['extension-key'] ?? '', 'locked' => ltrim($pkg['version'], 'v'),
        'locked_core' => $locked, 'abandoned' => false, 'majors' => []];
    $releases = fetchPackage($name, $pdir);
    foreach ($targets as $t) {
        $probe = $t . '.' . LTS_MINOR[$t] . '.99';
        if (satisfies($probe, $locked)) {
            $row['majors'][$t] = ['status' => 'ok', 'version' => $row['locked'], 'core' => $locked];
            continue;
        }
        if ($releases === null) {
            $row['majors'][$t] = ['status' => 'unknown', 'version' => null, 'core' => null];
            continue;
        }
        $best = null;
        foreach ($releases as $r) {
            $rv = (string)($r['version'] ?? '');
            if (!$unstable && !isStable($rv)) {
                continue;
            }
            $rc = coreConstraint($r);
            if ($rc !== null && satisfies($probe, $rc)) {
                if ($best === null || version_compare(ltrim($rv, 'v'), ltrim($best['version'], 'v'), '>')) {
                    $best = ['version' => $rv, 'core' => $rc, 'php' => $r['require']['php'] ?? ''];
                }
            }
        }
        $row['majors'][$t] = $best === null
            ? ['status' => 'none', 'version' => null, 'core' => coreConstraint($releases[0]) . ' (newest: ' . $releases[0]['version'] . ')']
            : ['status' => 'upgrade', 'version' => ltrim($best['version'], 'v'), 'core' => $best['core'], 'php' => $best['php']];
    }
    $row['abandoned'] = $releases !== null && !empty($releases[0]['abandoned']) ? ($releases[0]['abandoned'] === true ? true : $releases[0]['abandoned']) : false;
    $rows[] = $row;
}

$top = end($targets);
$blocking = array_filter($rows, fn($r) => in_array($r['majors'][$top]['status'], ['none', 'unknown'], true));

if ($format === 'json') {
    echo json_encode(['targets' => $targets, 'packages' => $rows, 'blocking' => array_values(array_map(fn($r) => $r['package'], $blocking))],
        JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";
} else {
    echo "# Third-party extensions vs. TYPO3 " . implode(', ', array_map(fn($t) => "$t." . LTS_MINOR[$t], $targets)) . "\n\n";
    echo '| Package | Key | Locked | ' . implode(' | ', array_map(fn($t) => "v$t", $targets)) . " |\n";
    echo '| --- | --- | --- |' . str_repeat(' --- |', count($targets)) . "\n";
    foreach ($rows as $r) {
        $cells = [];
        foreach ($targets as $t) {
            $m = $r['majors'][$t];
            $labels = ['ok' => 'ok', 'upgrade' => 'upgrade → ' . $m['version'], 'none' => '**none** (' . str_replace('|', '\\|', (string)$m['core']) . ')'];
            $cells[] = $labels[$m['status']] ?? '**unknown**';
        }
        $name = $r['package'] . ($r['abandoned'] ? ' *(abandoned' . (is_string($r['abandoned']) ? ' → ' . $r['abandoned'] : '') . ')*' : '');
        echo "| $name | {$r['key']} | {$r['locked']} | " . implode(' | ', $cells) . " |\n";
    }
    echo "\n" . count($rows) . ' package(s) checked; ' . count($blocking) . " block TYPO3 $top.\n";
    if ($blocking !== []) {
        echo "Blocking: " . implode(', ', array_map(fn($r) => $r['package'], $blocking)) . "\n";
    }
}
exit($blocking === [] ? 0 : 1);
