#!/usr/bin/env bash
# Render a GitHub step summary (markdown, stdout) from `rpr run --json` output.
# Usage: summary.sh <result.json> <rpr exit code>   one run
#        summary.sh --aggregate <results.json>      several runs: array of {config, exit_code, result} (run.sh)
#        summary.sh --line < <entry.json>           one plain log line for one {config, exit_code, result}
set -euo pipefail

# shellcheck disable=SC2016 # a jq program: $ and backticks are jq's, not the shell's
lib='
  def pct: (. * 100 | round) as $c
    | "\($c / 100 | floor).\($c % 100 | tostring | if length < 2 then "0" + . else . end)%";
  def dur: if . == null then "" elif . < 60000 then "\(. / 100 | round / 10)s"
    else "\(. / 60000 | floor)m \(. % 60000 / 1000 | floor)s" end;
  def cell: tostring | gsub("\\|"; "\\|") | gsub("\n"; " ");
  def code: if . == null or . == "" then "" else "`\(cell | gsub("`"; "'"'"'"))`" end;
  def errtext: .error | if type == "string" then . else tojson end;
  def survivors: (.survivors // []) | length > 0;
  def warnings: (.warnings // []) | length > 0;
  def survivor_table:
    "| Location | Mutator | Replacement | Status |",
    "|---|---|---|---|",
    (.survivors[] | "| `\("\(.file):\(.line):\(.column)" | cell)` | \(.mutator | cell) | \(.replacement | code) | \(.status | cell) |"),
    "";
  def warning_list: (.warnings[] | "- \(cell)"), "";
  def run_line: "run: `\(.run_dir // .run_id | cell)`";

  # One {config, exit_code, result} as one plain line for the job log.
  def log_line:
    (.config // "rpr") as $cfg | .result
    | "\($cfg): " + if has("error") then "error: \(errtext | gsub("\n"; " "))"
      elif .score == null then "nothing to mutate"
      else (.counts // {}) as $n
        | "score \(.score | pct) (\($n.killed // 0) killed, \($n.survived // 0) survived"
          + (if ($n.no_coverage // 0) > 0 then ", \($n.no_coverage) no coverage" else "" end)
          + (if ($n.timeout // 0) > 0 then ", \($n.timeout) timeout" else "" end)
          + ") — "
          + (if .passed then "passed" elif .engine_gate_failed then "failed: engine threshold"
             else "failed: below min score \(.min_score)" end)
      end;

  # One result, as its own summary.
  def single($code):
    if has("error") then
      "## rpr: error\n\n```\n\(errtext)\n```\n\nexit code \($code)"
    else
      (if .score == null then "## rpr: nothing to mutate in diff vs \(.base)"
       else "## rpr mutation score: \(.score | pct)" end),
      "",
      "**\(if .passed then "Passed" else "Failed" end)**"
        + (if .min_score != null then " (min score \(.min_score))" else "" end)
        + (if .engine_gate_failed then ", engine threshold failed" else "" end)
        + " · engine \(.engine) · diff vs \(.base)"
        + " · \(.ranges | if type == "array" then "\(length) ranges in \(map(.path) | unique | length) files" else "\(.) ranges" end)"
        + " · \(.duration_ms | dur)",
      "",
      (if (.counts // {}) | length > 0 then
        "| " + ([.counts | keys_unsorted[] | gsub("_"; " ")] | join(" | ")) + " |",
        "|" + ([.counts[] | "---:"] | join("|")) + "|",
        "| " + ([.counts[] | tostring] | join(" | ")) + " |",
        ""
       else empty end),
      (if survivors then "### Survivors (\(.survivors | length))", "", survivor_table else empty end),
      (if warnings then "### Warnings", "", warning_list else empty end),
      run_line
    end;

  # Several results: one table row per config, then survivors per config, then errors.
  def aggregate:
    map(.failed = (.result | has("error")))
    | ([.[] | select(.failed | not) | .result] | first(.[] | select(.base)) // {}) as $any
    | "## rpr: \(map(select(.result.passed == true)) | length) of \(length) configs passed",
      "",
      (if $any.base then "diff vs \($any.base)"
         + (if $any.min_score != null then " · min score \($any.min_score)" else "" end), "" else empty end),
      "| Config | Score | Killed | Survived | No coverage | Result | Duration |",
      "|---|---:|---:|---:|---:|---|---:|",
      (.[] | .config as $cfg | .result
        | if has("error") then [($cfg | code), "", "", "", "", "error", ""]
          else [($cfg | code),
                (if .score == null then "nothing to mutate" else .score | pct end),
                (.counts | .killed, .survived, .no_coverage | . // 0 | tostring),
                (if .passed then "passed" elif .engine_gate_failed then "failed (engine threshold)" else "failed" end),
                (.duration_ms | dur)]
          end
        | "| " + join(" | ") + " |"),
      "",
      (.[] | select((.failed | not) and (.result | survivors or warnings)) | .config as $cfg | .result
        | "### \($cfg | code)" + (if survivors then ": \(.survivors | length) survivors" else "" end),
          "",
          (if survivors then survivor_table else empty end),
          (if warnings then "Warnings:", "", warning_list else empty end),
          run_line,
          ""),
      (map(select(.failed)) | if length > 0 then
        "### Errors",
        "",
        (.[] | "\(.config | code) (exit code \(.exit_code)):", "", "```", (.result | errtext), "```", "")
       else empty end);
'

if [ "${1:-}" = --line ]; then
  jq -r "$lib log_line"
  exit 0
fi
if [ "${1:-}" = --aggregate ]; then
  jq -r "$lib aggregate" "$2"
  exit 0
fi

file=$1
code=${2:-}
if ! jq -e 'type == "object"' "$file" > /dev/null 2>&1; then
  printf '## rpr: error\n\nrpr exited with code %s and wrote no JSON report. See the step log.\n' "$code"
  exit 0
fi
jq -r --arg code "$code" "$lib single(\$code)" "$file"
