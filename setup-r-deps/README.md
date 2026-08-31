# setup-r-deps

Installs an R package's dependencies the PredictiveEcology way: pandoc,
geospatial system libraries, R itself, and the dependency install with a retry
fallback.

Extracted from the `R-CMD-check` reusable workflow so a job that is **not**
running `R CMD check` can reuse it — a benchmark, an ad-hoc matrix leg, a
coverage run with different flags. Previously that meant copy-pasting ~90 lines.

## Usage

```yaml
- uses: actions/checkout@v7
- uses: PredictiveEcology/actions/setup-r-deps@main
  with:
    r-version: release
    extra-packages: any::rcmdcheck
```

Pin to a tag or SHA rather than `@main` — see the note in the repo README.

## Inputs

| input | default | notes |
| --- | --- | --- |
| `r-version` | `release` | passed to `setup-r` |
| `dependencies` | `"all"` | R expression for `setup-r-dependencies` |
| `extra-packages` | `""` | newline-separated, appended |
| `pak-version` | `stable` | devel occasionally regresses |
| `cache-version` | `1` | bump to clear a poisoned dependency cache |
| `extra-repositories` | `""` | r-universe serves dev versions; opt in deliberately |
| `use-public-rspm` | `true` | Posit binaries |
| `ncpus` | `2` | |
| `pandoc` | `true` | set `false` for jobs that never render |
| `system-deps` | `true` | set `false` for a pure-R package |
| `post-install` | `""` | Rscript run after the install |
| `working-directory` | `.` | where DESCRIPTION lives |

## On timeouts

Composite-action steps do **not** support `timeout-minutes`
([actions/runner#1979](https://github.com/actions/runner/issues/1979)), and it
is not honoured on the step that *calls* a composite action either. The apt
steps are bounded with GNU `timeout` inside the `run:` block instead, which also
gives a per-command cap rather than one cap for the whole step. The dependency
retry uses `nick-fields/retry`, whose own `timeout_minutes` does work — composite
actions may `uses:` other actions.
