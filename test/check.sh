#!/usr/bin/env bash
# shellcheck disable=SC2016 # literal markdown backticks
# Renders the fixtures and asserts the key lines. Run: bash test/check.sh
set -euo pipefail
cd "$(dirname "$0")"
s=../summary.sh
bash $s pass.json 0  | grep -qF '## rpr mutation score: 72.73%'
bash $s pass.json 0  | grep -qF '| `packages/lib/src/x.ts:42:7` | ConditionalExpression | `false` | Survived |'
bash $s pass.json 0  | grep -qF '`"a\|b"`'
bash $s pass.json 0  | grep -qF '1m 23s'
bash $s pass.json 0  | grep -qxF 'run: `/home/runner/work/repo/repo/.git/reapr/runs/1793640000-4242`'
bash $s empty.json 0 | grep -qF '## rpr: nothing to mutate in diff vs origin/main'
jq 'del(.run_dir)' empty.json > "${TMPDIR:-/tmp}/rpr-no-run-dir.json"
bash $s "${TMPDIR:-/tmp}/rpr-no-run-dir.json" 0 | grep -qxF 'run: `1793640100-4243`'
bash $s error.json 2 | grep -qF 'no mutation engine detected'
bash $s error.json 2 | grep -qF '## rpr: error'
echo 'not json' > "${TMPDIR:-/tmp}/rpr-bad.json"
bash $s "${TMPDIR:-/tmp}/rpr-bad.json" 2 | grep -qF 'exited with code 2'

# run.sh against a fake rpr that prints a fixture per --config and exits as rpr would for it.
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"
cat > "$t/bin/rpr" << 'FAKE'
#!/usr/bin/env bash
cfg=
while [ $# -gt 0 ]; do [ "$1" != --config ] || cfg=$2; shift; done
case $cfg in
  *api*) f=pass ;; *docs*) f=empty ;; *web*) f=fail ;; *crash*) exit 3 ;; *) f=error ;;
esac
cat "$FIXTURES/$f.json"
if jq -e 'has("error")' "$FIXTURES/$f.json" > /dev/null; then exit 2; fi
jq -e .passed "$FIXTURES/$f.json" > /dev/null || exit 1
FAKE
chmod +x "$t/bin/rpr"
run() { # run <configs> [config]: exit code in $rc, summary in $t/summary.md, outputs in $t/out
  : > "$t/summary.md"
  : > "$t/out"
  rc=0
  REAPR_CONFIGS=$1 REAPR_CONFIG=${2:-} REAPR_BASE=main REAPR_MIN_SCORE='' FIXTURES=$PWD PATH="$t/bin:$PATH" \
    RUNNER_TEMP=$t GITHUB_OUTPUT=$t/out GITHUB_STEP_SUMMARY=$t/summary.md bash ../run.sh > /dev/null || rc=$?
}
has() { grep -qxF "$1" "$t/summary.md" || { echo "missing in summary: $1" >&2; cat "$t/summary.md" >&2; exit 1; }; }
hasnt() { if grep -qF "$1" "$t/summary.md"; then echo "unexpected in summary: $1" >&2; exit 1; fi; }
out() { grep -qxF "$1" "$t/out" || { echo "missing in outputs: $1" >&2; cat "$t/out" >&2; exit 1; }; }

# Single config: summary and outputs as before.
run '' stryker.api.config.mjs
[ "$rc" = 0 ]
has '## rpr mutation score: 72.73%'
out 'score=72.72727272727273'
out 'passed=true'
out 'run-id=1793640000-4242'
[ "$(jq -r '.[0].config' "$(sed -n 's/^results=//p' "$t/out")")" = stryker.api.config.mjs ]

# Three configs (CRLF, a comment, a blank line, padding): pass with survivors, nothing to mutate, gate failure.
run $'# one per package\r\nstryker.api.config.mjs\r\n\r\n  stryker.docs.config.mjs \r\nstryker.web.config.mjs\r\n'
[ "$rc" = 1 ]
has '## rpr: 2 of 3 configs passed'
has 'diff vs origin/main · min score 50'
has '| `stryker.api.config.mjs` | 72.73% | 14 | 1 | 1 | passed | 1m 23s |'
has '| `stryker.docs.config.mjs` | nothing to mutate | 0 | 0 | 0 | passed | 0.4s |'
has '| `stryker.web.config.mjs` | 40.00% | 2 | 2 | 1 | failed (engine threshold) | 9.5s |'
has '### `stryker.api.config.mjs`: 2 survivors'
has '### `stryker.web.config.mjs`: 3 survivors'
has '| `packages/web/src/form.ts:12:5` | EqualityOperator | `a <= b` | Survived |'
hasnt '### `stryker.docs.config.mjs`'
hasnt '### Errors'
out 'score='
out 'passed=false'
out 'run-id='
cp "$t/summary.md" "$t/three.md"
results=$(sed -n 's/^results=//p' "$t/out")
[ "$(jq -c 'map([.config, .exit_code, .result.run_id])' "$results")" = \
  '[["stryker.api.config.mjs",0,"1793640000-4242"],["stryker.docs.config.mjs",0,"1793640100-4243"],["stryker.web.config.mjs",1,"1793640200-4244"]]' ]

# An error (JSON error, and a crash without JSON) beats a gate failure; every config still runs.
run $'stryker.api.config.mjs\nstryker.web.config.mjs\nstryker.broken.config.mjs\nstryker.crash.config.mjs'
[ "$rc" = 2 ]
has '## rpr: 1 of 4 configs passed'
has '| `stryker.broken.config.mjs` |  |  |  |  | error |  |'
has '### Errors'
has '`stryker.broken.config.mjs` (exit code 2):'
has 'no mutation engine detected in /work/app (looked for stryker.config.*)'
has '`stryker.crash.config.mjs` (exit code 3):'
has 'rpr exited with code 3 and wrote no JSON report. See the step log.'
out 'passed=false'

# All pass: exit 0.
run $'stryker.api.config.mjs\nstryker.docs.config.mjs'
[ "$rc" = 0 ]
out 'passed=true'

# Release resolution: pinned versions use the rpr-v<version> tags (reapr-corp/reapr#18).
res() { REAPR_VERSION="$1" bash ../resolve-release.sh; }
[ "$(res latest)" = "$(printf 'url=https://github.com/reapr-corp/reapr/releases/latest/download\ntag=')" ]
[ "$(res 0.2.0)" = "$(printf 'url=https://github.com/reapr-corp/reapr/releases/download/rpr-v0.2.0\ntag=rpr-v0.2.0')" ]
[ "$(res v0.2.0)" = "$(res 0.2.0)" ]
if res '1;rm' >/dev/null 2>&1; then echo "invalid version accepted"; exit 1; fi

[ "${SHOW:-}" = "" ] || cat "$t/three.md"
echo ok
