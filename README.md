# actions

Collection of GitHub Actions used by the Predictive Ecology group to test
packages, `SpaDES` modules, and render `SpaDES` module manuals. Two kinds live
here: **composite actions**, used as a step inside your own job, and **reusable
workflows**, called as a whole job.

# Which ref to use

Use `@main`.

That is the org standard, settled in
[PredictiveEcology/SpaDES.tools#124](https://github.com/PredictiveEcology/SpaDES.tools/pull/124),
and it deliberately reverses the advice this file used to give. Three reasons:

1. **A pin does not freeze what it pins.** The reusable workflows resolve the
   composite actions they call at run time — `R-CMD-check.yaml` uses
   `PredictiveEcology/actions/setup-r-deps@main` — so a caller pinned to a tag
   or a SHA still gets `main`'s actions. The isolation a pin appears to buy was
   never real.
2. **`main` is gated.** [`self-test.yaml`](.github/workflows/self-test.yaml)
   exercises every composite action here against the pull request's own
   checkout, so a change cannot reach consumers without passing first.
3. **The published tags carry a known-bad `install-spatial-deps`.** Every tag
   from `v0.1` through `v0.5` still adds `ppa:ubuntugis/ubuntugis-unstable`,
   which installs libgdal37 while Posit's noble binary cache builds
   `sf`/`terra`/`quickPlot` against the Ubuntu-default libgdal34. The mismatch
   surfaces as `libgdal.so.34: cannot open shared object file` at lazy-load
   time — a check failure that reads as the package's fault. Pinning a tag
   today pins that bug; `main` is where it is fixed.

See [NEWS.md](https://github.com/PredictiveEcology/actions/blob/main/NEWS.md)
for a description of the changes made at each version tag.

# Composite actions

Used as a step. For details and example usage, see each action's `README`.

| action | what it does |
| --- | --- |
| [`setup-r-deps`](setup-r-deps) | pandoc, geospatial system libraries, R, and an R package's dependencies with a retry fallback — the dependency half of `R-CMD-check.yaml`, reusable on its own |
| [`stage-gdrive-auth`](stage-gdrive-auth) | decodes a `GOOGLEDRIVE_AUTH` user OAuth token onto the runner and reports its path; rejects service-account keys |
| [`install-spatial-deps`](install-spatial-deps) | GDAL/GEOS/PROJ and friends on Ubuntu Linux and macOS |
| [`install-Require`](install-Require) | installs `remotes` and `Require` |
| [`install-Rmd-pkgs`](install-Rmd-pkgs) | packages needed to render `SpaDES` module manuals — **requires `install-Require` first** |
| [`install-SpaDES`](install-SpaDES) | the `SpaDES` packages — **requires `install-Require` first** |

# Reusable workflows

Called as a job (`uses:` at the job level, not the step level). Each file's
header comment carries a complete calling example and the full input list.

| workflow | what it does |
| --- | --- |
| [`R-CMD-check.yaml`](.github/workflows/R-CMD-check.yaml) | `R CMD check` across an OS/R-version matrix, extensible per leg via `extra-config` |
| [`test-coverage.yaml`](.github/workflows/test-coverage.yaml) | `covr` + Codecov upload |
| [`pkgdown.yaml`](.github/workflows/pkgdown.yaml) | builds the pkgdown site and deploys it to `gh-pages` |
| [`test-downstream.yaml`](.github/workflows/test-downstream.yaml) | checks each downstream package against the *caller's* branch rather than against CRAN |

[`self-test.yaml`](.github/workflows/self-test.yaml) is internal: it is this
repository's own gate on `main`, not something to call.

# More information on GitHub Actions

<https://github.com/r-lib/actions>
