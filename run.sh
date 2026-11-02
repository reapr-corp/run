#!/usr/bin/env bash
# The action's Run step: rpr once per engine config, then the step summary and the step outputs.
# Env: REAPR_BASE, REAPR_MIN_SCORE, REAPR_CONFIG, REAPR_CONFIGS (one path per line, blank lines and # comments
# ignored), RUNNER_TEMP, GITHUB_OUTPUT, GITHUB_STEP_SUMMARY. Exit: 2 if any run errored, else 1 if any gate
# failed, else 0.
set -euo pipefail
here=$(dirname "$0")

cfgs=()
while IFS= read -r line; do
  line=${line#"${line%%[![:space:]]*}"} # trim both ends, which also drops the \r of CRLF lines
  line=${line%"${line##*[![:space:]]}"}
  case $line in '' | '#'*) ;; *) cfgs+=("$line") ;; esac
done <<< "${REAPR_CONFIGS:-}"
multi=${#cfgs[@]}
[ "$multi" -gt 0 ] || cfgs=("${REAPR_CONFIG:-}") # one run; empty config = detected

dir=$(mktemp -d "$RUNNER_TEMP/rpr-XXXXXX") # unique per invocation, so two uses in one job keep their results
results="$dir/results.json"
worst=0 i=0
for cfg in "${cfgs[@]}"; do
  i=$((i + 1))
  out="$dir/result-$i.json"
  args=(run --diff "origin/$REAPR_BASE" --json)
  [ -z "${REAPR_MIN_SCORE:-}" ] || args+=(--min-score "$REAPR_MIN_SCORE")
  [ -z "$cfg" ] || args+=(--config "$cfg")

  [ "$multi" -eq 0 ] || echo "::group::rpr --config $cfg"
  code=0
  rpr "${args[@]}" > "$out" || code=$?
  [ "$multi" -eq 0 ] || echo "::endgroup::"

  jq -nc --arg cfg "$cfg" --argjson code "$code" --rawfile raw "$out" '{
    config: (if $cfg == "" then null else $cfg end),
    exit_code: $code,
    result: (($raw | try fromjson catch null) | if type == "object" then .
      else {error: "rpr exited with code \($code) and wrote no JSON report. See the step log."} end)
  }' >> "$dir/results.jsonl"
  # The result in the job log too, readable without opening the summary.
  tail -n 1 "$dir/results.jsonl" | bash "$here/summary.sh" --line

  case $code in 0 | 1) rc=$code ;; *) rc=2 ;; esac
  [ "$rc" -le "$worst" ] || worst=$rc
done
jq -s . "$dir/results.jsonl" > "$results"

if [ "$multi" -gt 0 ]; then
  bash "$here/summary.sh" --aggregate "$results" >> "$GITHUB_STEP_SUMMARY"
else
  bash "$here/summary.sh" "$out" "$code" >> "$GITHUB_STEP_SUMMARY"
fi

jq -r --argjson multi "$multi" '
  if $multi > 0 then "score=", "passed=\(all(.[]; .result.passed == true))", "run-id="
  else .[0].result | "score=\(.score // "")", "passed=\(.passed // false)", "run-id=\(.run_id // "")" end
' "$results" >> "$GITHUB_OUTPUT"
printf 'results=%s\n' "$results" >> "$GITHUB_OUTPUT"
exit "$worst"
