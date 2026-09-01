# PredictiveEcology/actions (development)

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

