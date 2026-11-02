# reapr-corp/run

GitHub Action for [Reapr](https://github.com/reapr-corp/reapr): mutation testing scoped to the pull request diff.
Installs the `rpr` release binary, runs `rpr run --diff origin/<base> --json` (once, or once per engine config),
writes a job summary (score, counts, survivors, warnings) and exits with rpr's exit code.
The step log also gets one plain line per config with its result, for example
`stryker.api.config.mjs: score 94.12% (32 killed, 2 survived) — passed`, `... : nothing to mutate`,
`... — failed: engine threshold` or `...: error: <message>`.

## Requirements

Linux runners only for now: `ubuntu-latest`, or Blacksmith Ubuntu labels such as `blacksmith-2vcpu-ubuntu-2404`
(x86_64 and aarch64). On any other runner the action fails with exit code 2.

Reapr runs your own engine config; install the engine and your test deps before this step.

## Usage

```yaml
on: pull_request

jobs:
  rpr:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0 # full history, so origin/<base>...HEAD has a merge base
      - uses: actions/setup-node@v5
        with:
          node-version: 22
          cache: npm
      - run: npm ci # rpr runs your engine (StrykerJS) with your installed deps
      - name: rpr
        uses: reapr-corp/run@v1
        id: rpr
        with:
          min-score: 80
```

No token is needed: the action downloads the installer from the public `reapr-corp/reapr` releases.

With a shallow checkout (the `actions/checkout` default) the action fetches the base branch and unshallows
the repository itself. `fetch-depth: 0` is the simple, predictable path.

### Monorepo: several configs

With one engine config per package, list them in `configs`, one path per line. The action installs rpr once and
runs every config in the same step, one after the other. It never stops at the first failure: every config runs,
and the job summary combines the results.

```yaml
      - run: npm ci # once, for all packages
      - name: rpr
        uses: reapr-corp/run@v1
        id: rpr
        with:
          configs: |
            # one per package; blank lines and # comments are ignored
            stryker.api.config.mjs
            stryker.web.config.mjs
            stryker.worker.config.mjs
```

Each config keeps its own threshold: set `thresholds.break` in that config, and a package below it fails the
gate (exit code 1). `min-score`, when set, applies to every config. Each config's `mutate` patterns decide which
changed files it mutates, so a config whose package the diff does not touch reports `nothing to mutate`.

The summary has one row per config (score or `nothing to mutate`, killed, survived, no coverage, passed, failed
or error, duration), then the survivors of each config that has any, then the errors. The step exits with:
2 if any config errored, else 1 if any config failed its gate, else 0.

`config` and `configs` are mutually exclusive: setting both is an error (exit code 2).

### Private fork or mirror

`github-token` is only for installing from a private fork or mirror of the Reapr releases (a fork of this action
pointed at it). With a token, the action downloads the installer and the archives through the GitHub API
(`gh release download`, preinstalled on GitHub-hosted runners) and installs from that local copy. The token
needs read access to that repository's contents.

## Inputs

| Input | Default | Description |
|---|---|---|
| `base` | `${{ github.base_ref }}` | Base branch. Required outside `pull_request` events. |
| `min-score` | | Fail when the score is below this value (0-100). With `configs`, applies to each config. |
| `config` | detected | Engine config path, relative to `working-directory`. Not with `configs`. |
| `configs` | | Several engine config paths, one per line, relative to `working-directory`. Blank lines and `#` comments are ignored. Not with `config`. |
| `working-directory` | `.` | Project directory. |
| `version` | `latest` | Reapr version (`0.1.0`), or `latest`. |
| `github-token` | | Not needed for the public releases. Only for a private fork or mirror; needs `gh` on the runner. |

## Outputs

| Output | Description |
|---|---|
| `score` | Mutation score, empty when nothing was mutated, on error, and with `configs` (read each score from `results`). |
| `passed` | `true` or `false`. With `configs`, `true` only when every config passed. |
| `run-id` | Run id (the run record is in `<git dir>/reapr/runs/<run-id>/`), empty on error and with `configs` (see `results`). |
| `results` | Path to a JSON file holding an array with one entry per run: `{"config": ..., "exit_code": ..., "result": ...}`. `result` is the `rpr run --json` document, or `{"error": "..."}` on exit code 2; `config` is `null` when it was detected. Set with and without `configs`. |

For example, the scores per config: `jq -r '.[] | "\(.config) \(.result.score)"' "$RESULTS"` with
`RESULTS: ${{ steps.rpr.outputs.results }}` in the step's `env`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Passed (also when nothing in the diff was mutated). With `configs`: every config passed. |
| 1 | Score below `min-score`, or the engine's own threshold failed. With `configs`: at least one config failed and none errored. |
| 2 | Error (not a Linux runner, no base, `config` and `configs` both set, install failure, no engine detected, engine crash, ...). With `configs`: at least one config errored. |

## Telemetry

rpr sends one anonymous usage event per run ([TELEMETRY.md](https://github.com/reapr-corp/reapr/blob/main/TELEMETRY.md)).
The action sets `RPR_VIA_ACTION=1` for rpr, so the event says it came through this action (`via_action: true`);
nothing else is added. Turn telemetry off with `DO_NOT_TRACK: 1` in the job's `env`.

## Issues and questions

This repository has no issue tracker. Report bugs with the
[Reapr bug form](https://github.com/reapr-corp/reapr/issues/new?template=bug_report.yml) (choose
"GitHub Action" as the component) and ask questions in
[Reapr Discussions](https://github.com/reapr-corp/reapr/discussions). Fixes made here reference the issue
there.

## License

MIT
