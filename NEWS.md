# PredictiveEcology/actions (development)

- **New composite action `setup-r-deps`**, extracted from the `R-CMD-check`
  reusable workflow: pandoc (with retries), geospatial system libraries, R
  itself, and the dependency install. A job that is not running `R CMD check`
  can now reuse the dependency setup instead of copy-pasting ~90 lines.
  `R-CMD-check.yaml` drops from 375 to ~180 lines;
- **New composite action `stage-gdrive-auth`**, extracted from the same
  workflow. The ~55-line credential-staging block was duplicated verbatim
  between `R-CMD-check.yaml` and `test-coverage.yaml`, and the two copies had
  already drifted — the diagnostic that exists to make a dropped secret visible
  was less informative in one of them;
- `R-CMD-check.yaml` gains **`cache-version`** and **`extra-repositories`**
  inputs. `cache-version` was previously unreachable, so a caller could not
  clear a poisoned dependency cache without a PR to this repo;
- **the dependency "retry fallback" has been removed** (it was fixed earlier in
  this same development cycle, then found not to be worth having). It was never
  a retry: the primary path is `pak::lockfile_install()` (`upgrade = FALSE`),
  while the fallback called `pak::local_install_dev_deps()`, which defaults to
  `upgrade = TRUE` — bypassing the lockfile and the cache to resolve a *more*
  aggressive set than the one that had just failed. Paired with
  `continue-on-error: true` on the primary step, a genuinely broken dependency
  bought ~90 minutes of futile reinstallation instead of an immediate red. It is
  also unnecessary now: pak retries failed HTTP requests by default (pak 0.11.0
  NEWS — exponential backoff, honouring `Retry-After`, covering downloads and
  not just metadata) and `pak-version` defaults to `stable`, i.e. the current
  CRAN release. `continue-on-error` is gone from the dependency step with it, so
  a failed install is now red immediately;
- **all four reusable workflows now go through `setup-r-deps`.** `pkgdown.yaml`,
  `test-coverage.yaml` and `test-downstream.yaml` each carried their own apt
  block, their own `setup-pandoc` (with differing retry counts) and their own
  hardcoded `extra-repositories`; `test-downstream.yaml` also carried a stale
  copy of the retry fallback that dropped `extra-packages`. As a side effect all
  three now get the RcppParallel/oneTBB rebuild probe that only `R-CMD-check`
  had — an ABI-mismatched binary installs cleanly and only fails at `dlopen`;
- `setup-r-deps` gains **`needs`** (`Config/Needs/<field>` entries, which is how
  `pkgdown.yaml` still gets `Config/Needs/website`) and **`pre-install`** (an
  Rscript run after `setup-r` and *before* dependency resolution).
  `pre-install` is what lets `test-downstream.yaml` keep stripping the
  downstream's `Remotes:` pin in the only window where that works — after R
  exists, before pak resolves anything;
- `R-CMD-check.yaml` gains **`system-deps`** and **`pandoc`** inputs, forwarded
  to `setup-r-deps`. It has always gated its geospatial install on
  `system-deps`, but nothing forwarded the input, so no caller could turn it
  off. Both default to `true`, and neither is derived from the `DESCRIPTION`:
  `reproducible` and `SpaDES.project` reach terra/sf/raster/geodata through
  `Suggests` only, so any rule based on hard dependencies would get exactly
  those packages wrong. `pkgdown.yaml`, `test-coverage.yaml` and
  `test-downstream.yaml` gain `system-deps` too (and `pandoc`, except
  `pkgdown.yaml`, which cannot render without it);
- `pkgdown.yaml`, `test-coverage.yaml` and `test-downstream.yaml` gain
  **`cache-version`** and **`extra-repositories`** inputs, matching
  `R-CMD-check.yaml`. `cache-version` was previously unreachable in all three,
  so a caller could not clear a poisoned dependency cache without a PR to this
  repo — and a stale cache was the actual root cause of both libgdal ABI
  incidents;
- **all four reusable workflows now declare `permissions:`.** They previously
  declared none, so a caller whose repository default is read/write handed them
  — and every third-party package they install — a writable `GITHUB_TOKEN`.
  Three are `read-all` (matching r-lib/actions' own templates); `pkgdown`'s job
  takes `contents: write`, which its gh-pages deploy genuinely needs;
- **`install-spatial-deps` now documents why it still exists**, in both the
  action and its README: the SpaDES *module* repositories have no `DESCRIPTION`
  (dependencies live in `defineModule(reqdPkgs = ...)`) and install via
  `Require::Require()` rather than pak, and `Require`'s `.onLoad` deliberately
  sets `PKG_SYSREQS=false`/`PKG_SYSREQS_SUDO=false` because CRAN treats a
  package shelling out to `sudo` as machine hijacking. On that path nothing
  else installs GDAL. Without the note the action reads as dead code now that
  `setup-r-deps` exists. Its ABI comment is also corrected: it no longer blames
  `quickPlot` (which is `NeedsCompilation: no` and links nothing — it is merely
  the package that loads sf/terra first), and it names noble's package
  correctly (`libgdal34t64`, providing `libgdal.so.34`);
- `self-test.yaml` now exercises `setup-r-deps`' `pre-install` and `needs`
  inputs. An unknown input to a composite action is a *warning*, not an error,
  so a rename would otherwise have surfaced as a pkgdown build quietly missing
  its tooling;
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
   `uses:` other actions, so `nick-fields/retry`'s `timeout_minutes` works. This
   was used for the dependency retry, which has since been removed; the
   technique remains available for a step that needs a real cap.
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

