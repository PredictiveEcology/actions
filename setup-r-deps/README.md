# setup-r-deps

Installs an R package's dependencies the PredictiveEcology way: pandoc,
geospatial system libraries, R itself, and the dependency install.

Extracted from the `R-CMD-check` reusable workflow so a job that is **not**
running `R CMD check` can reuse it — a benchmark, an ad-hoc matrix leg, a
coverage run with different flags. Previously that meant copy-pasting ~90 lines.
All four reusable workflows in this repository now go through it.

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
| `needs` | `""` | `Config/Needs/<field>` entries (e.g. `website` for pkgdown) |
| `pak-version` | `stable` | devel occasionally regresses |
| `cache-version` | `1` | bump to clear a poisoned dependency cache |
| `extra-repositories` | `""` | r-universe serves dev versions; opt in deliberately |
| `use-public-rspm` | `true` | Posit binaries |
| `ncpus` | `2` | |
| `pandoc` | `true` | set `false` for jobs that never render |
| `system-deps` | `true` | set `false` for a pure-R package |
| `pre-install` | `""` | Rscript run after `setup-r`, before the dependency install |
| `post-install` | `""` | Rscript run after the install |
| `working-directory` | `.` | where DESCRIPTION lives |

## No dependency-install retry

There used to be a "retry fallback" after the dependency install. It was not a
retry: the primary path is `pak::lockfile_install()` (`upgrade = FALSE`), while
the fallback called `pak::local_install_dev_deps()`, which defaults to
`upgrade = TRUE` — bypassing the lockfile and the cache to resolve a *more*
aggressive set than the one that had just failed. With `continue-on-error: true`
on the primary step, a genuinely broken dependency became ~90 minutes of futile
reinstallation instead of an immediate red.

It is also unnecessary: pak retries failed HTTP requests by default (pak 0.11.0
NEWS — exponential backoff, honouring `Retry-After`, covering package downloads
and not just metadata), and `pak-version` defaults to `stable`, i.e. the current
CRAN release. Transient network failures are handled one layer down now.

## On timeouts

Composite-action steps do **not** support `timeout-minutes`
([actions/runner#1979](https://github.com/actions/runner/issues/1979)), and it
is not honoured on the step that *calls* a composite action either. The apt
steps are bounded with GNU `timeout` inside the `run:` block instead, which also
gives a per-command cap rather than one cap for the whole step.
