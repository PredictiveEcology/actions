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

`@main` is the org standard — see
[Which ref to use](../README.md#which-ref-to-use) in the repo README. This
file used to say the opposite ("pin to a tag or SHA"), which was wrong twice
over: **no published tag contains this action at all** (`setup-r-deps` and
`stage-gdrive-auth` were added after `v0.5`, so `@v0.5` and earlier resolve to
"action not found"), and every tag that does exist still carries an
`install-spatial-deps` that adds the ubuntugis-unstable PPA — the libgdal37 /
libgdal34 ABI mismatch this action exists to avoid.

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

## License

The scripts and documentation in this project are released under the [MIT License](LICENSE)

## Contributions

Contributions are welcome!
