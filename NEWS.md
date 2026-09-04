# PredictiveEcology/actions (development)

- **New reusable workflow `render-module-rmd.yaml`**, for SpaDES modules. Until
  now every module repository carried a hand-generated copy of this job, written
  once by `SpaDES.core::use_gha()` and never regenerated. The survey in #36 found
  74 repositories carrying it across 96 repository/branch combinations, split
  into two generations that had drifted apart: 46 combinations still on
  `ubuntu-20.04` with `actions/checkout@v2` and `r-lib/actions/setup-r@v1`, and
  50 on the newer shape pinning five actions from this repository at `@v0.2`,
  `@v0` or `@v0.0.1`. Those pins are the main thing blocking retirement of
  `v0.1`-`v0.5`. A caller now supplies its triggers and the module name; the
  pins live here. Fixes carried in by the move: the `[skip-ci]` guard tested
  `commits[0]`, the *oldest* commit in a push, and was absent entirely on pull
  requests -- it now uses `head_commit` as elsewhere (#34); the job had no
  `concurrency` group, so superseded runs were never cancelled (#30); the
  hand-written `apt-get install` had no `apt-get update`, no retries and no
  timeout, the exact shape that burned two LandWebUtils jobs for 6h on
  2026-08-19; and the commit step ran on pull requests too, where the push
  cannot succeed and failed silently every time. Rendering and committing are
  now separate jobs, as in `citation.yaml`, because rendering executes the
  module's own `.Rmd` and that must not share a job with a write-scoped token.
  Inputs: `module` (required), `r-version`, `system-deps`, `extra-apt`;

- **New reusable workflow `citation.yaml`**, which regenerates `CITATION.cff`
  from `DESCRIPTION` and `inst/CITATION`. Four repos (`reproducible`, `SpaDES`,
  `SpaDES.core`, `SpaDES.tools`) carried near-identical hand-rolled copies of
  this job; all four now call the template with **no overrides**. Two things
  this centralises. First, the `install-spatial-deps` pin: a hand-rolled caller
  names that action directly, so the four had drifted to `@v0.1`, `@v0.2` and a
  raw SHA, and every tag `v0.1`-`v0.5` still adds the `ubuntugis-unstable` PPA
  (libgdal37), ABI-incompatible with Posit's noble binaries. The action is now
  reached through `setup-r-deps`, so the pin is internal here and moves once.
  Second, a privilege split that previously existed in `SpaDES.tools` alone:
  generating the file installs and runs third-party R code, committing it needs
  a write-scoped token, and those must not share a job -- so `build` runs with
  `contents: read` and uploads an artifact, and `commit` runs with
  `contents: write` and nothing but git. Callers must grant `contents: write`
  on the calling job, since a called workflow can only reduce permissions.
  Inputs: `extra-packages`, `dependencies`, `system-deps`. `pandoc` is
  deliberately not an input -- nothing in this job renders;

- **`[skip-ci]` is now honoured by every reusable workflow**, org-wide.
  GitHub stops a run itself for its own keywords (`[skip ci]`, `[ci skip]`,
  `[no ci]`, `[skip actions]`, `[actions skip]`), but the hyphenated
  `[skip-ci]` is a PE convention it does not know about, so each caller that
  wanted it was carrying its own `if:`. Moving to a thin caller silently lost
  it. The guard now lives here, so callers do not need one.

  Note it tests `github.event.head_commit.message` -- the **tip** of the push,
  matching GitHub's own semantics. The hand-rolled versions tested
  `github.event.commits[0].message`, the *oldest* commit in the push, so a
  `[skip-ci]` on the tip of a multi-commit push used to be ignored. It is null
  on `pull_request` and `schedule`, so those always run;

- **New reusable workflow `revdeps.yaml`**, wrapping the `revdeps-check`
  composite action in the job harness callers were otherwise writing by hand
  (checkout, geospatial system libraries, R, dependency install). quickPlot and
  Require had each written their own; quickPlot's ran a three-OS matrix on
  every `pull_request`, which spends hours of runner time on a signal almost no
  PR changes. The default is a single `ubuntu-latest`/`release` leg, with
  `config` taking a JSON matrix for packages that genuinely need more.

  Inputs: `config`, `cranonly`, `quiet`, `timeout`, `extra-packages`,
  `extra-repositories`. Callers own their own triggers -- `workflow_dispatch`
  plus a weekly `schedule` is the sane default, given the composite action's
  own warning that revdep checks are too heavy for standard runners;

- **Fixed: the concurrency groups added for cancelling superseded runs
  deadlocked every caller that declared its own.** Inside a called workflow
  `github.workflow` resolves to the *caller's* workflow name, so
  `${{ github.workflow }}-${{ github.ref }}` here produced the identical key to
  the same (very common) expression in a caller. The called workflow then waited
  on a group its own parent held, and GitHub cancelled the run before any job
  started — `conclusion: failure` with zero jobs and no check runs, which does
  not look like a concurrency problem. The groups now carry a `-reusable`
  suffix, so they cannot collide. **Callers need no change**: those that declare
  their own concurrency work again untouched, and those that do not still get
  the cancellation behaviour. Affected every caller pinned to `@main` from
  2026-09-01 04:05Z until this fix;

- **New composite action `setup-r-deps`**, extracted from the `R-CMD-check`
  reusable workflow: pandoc (with retries), geospatial system libraries, R
  itself, and the dependency install with its retry fallback. A job that is not
  running `R CMD check` can now reuse the dependency setup instead of
  copy-pasting ~90 lines. `R-CMD-check.yaml` drops from 375 to ~180 lines;
- **New composite action `stage-gdrive-auth`**, extracted from the same
  workflow. The ~55-line credential-staging block was duplicated verbatim
  between `R-CMD-check.yaml` and `test-coverage.yaml`, and the two copies had
  already drifted — the diagnostic that exists to make a dropped secret visible
  was less informative in one of them;
- `R-CMD-check.yaml` gains **`cache-version`** and **`extra-repositories`**
  inputs. `cache-version` was previously unreachable, so a caller could not
  clear a poisoned dependency cache without a PR to this repo;
- the dependency **retry fallback now mirrors the primary step's `dependencies`
  and `extra-packages`**. It previously used pak's own narrower defaults and
  dropped `extra-packages` entirely, so a fallback silently checked a different
  dependency set than the one requested — and `continue-on-error: true` on the
  primary step made that invisible in the UI. It now also emits a warning when
  it fires;
- **`install-spatial-deps` no longer adds the `ubuntugis-unstable` PPA.** That
  PPA installs libgdal37, which is ABI-incompatible with the binaries in
  Posit's noble cache — the reusable workflows have refused it for months while
  this action still added it, so the org shipped two contradictory answers to
  the same question. It also now configures `PROJ_DATA` on macOS (which the
  workflows did and this action did not, so its consumers hit
  "Cannot find proj.db") and asserts the installed library versions rather than
  proceeding silently;
- **`install-Require`'s default `GitTag` is now `development`.** The default was
  `master`, a branch that no longer exists on `PredictiveEcology/Require`, so
  the default was dead code that would hard-fail if anyone relied on it.

## A note on timeouts in composite actions

`timeout-minutes` is not supported for steps inside a composite action
([actions/runner#1979](https://github.com/actions/runner/issues/1979)), and it
is not honoured on the step that *calls* one either. Three alternatives, all
used here:

1. **GNU `timeout` inside the `run:` block** — what the apt steps use. Bounds
   each command rather than the whole step. Linux/macOS only; Windows runners
   have no GNU `timeout`.
2. **An action that implements its own timeout** — composite actions may
   `uses:` other actions, so `nick-fields/retry`'s `timeout_minutes` works. Used
   for the dependency retry.
3. **`timeout-minutes` on the calling job** — a coarse backstop that kills the
   whole job, not the step.

# PredictiveEcology/actions (v0.4)

- **`GOOGLEDRIVE_AUTH` is no longer a job-level `env:`.** It is now staged to a
  file by a dedicated step placed *after* all dependency installation, and
  handed only to the step that runs the tests (`check-r-package` /
  `Test coverage`). Previously it sat in the environment of every step,
  including those that install third-party packages from GitHub;
- `GOOGLEDRIVE_AUTH` (and `CODECOV_TOKEN`) are now **declared** under
  `workflow_call.secrets`, so callers can name them explicitly instead of
  relying on `secrets: inherit`. Existing `secrets: inherit` callers keep
  working unchanged;
- the staging step accepts the secret **base64-encoded** (preferred) or as raw
  JSON. Base64 is single-line and therefore survives Windows runners, where a
  multi-line `env:` value arrives empty and silently disabled Drive-backed
  tests;
- a configured-but-unusable `GOOGLEDRIVE_AUTH` now emits a workflow **warning**
  instead of skipping silently, so "credential missing" no longer looks
  identical to "tests passed";
- `actions/checkout` v5 -> v7 and `nick-fields/retry` v3 -> v4 (both move off
  the deprecated Node.js 20 runtime);

- `R-CMD-check` reusable workflow now rebuilds from source any installed package that links `RcppParallel` but fails to load, so an `RcppParallel` TBB ABI change (e.g. 6.0.0's move to oneTBB) does not break every downstream package's CI while repositories catch up;

- added package caching to `revdeps-check` action;
- improved reporting in `revdeps-check` action;
- allow `revdeps-check` to check CRAN packages only;

# PredictiveEcology/actions (v0.3)

- fixed `revdeps-check` action to work with `r-universe` repos;

# PredictiveEcology/actions (v0.2)

- update actions using `ubuntu-latest` to work with Ubuntu 24.04;

# PredictiveEcology/actions (v0.1)

- minor tweaks to existing actions, including improved documentation;
- added `install-spatial-deps` and `revdeps-check` actions;

# PredictiveEcology/actions (v0.0)

- initial release;
- added actions `install-Require`, `install-Rmd-pkgs` and `install-SpaDES`;

