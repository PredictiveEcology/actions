# PredictiveEcology/actions (development)

- **`testthat-module.yaml` and `pkgdown-module.yaml` no longer install
  SpaDES.core@development explicitly.** `install-SpaDES` installs
  `SpaDES.experiment@development`, whose `DESCRIPTION` has
  `Remotes: PredictiveEcology/SpaDES.core@development`, so a development SpaDES.core is
  already present and the step re-requested the same ref. Verified by running both
  workflows against `fireSense_SpreadFit` with the step removed (runs 34672314858 and
  34672314866): `install-SpaDES` alone produced
  `SpaDES.core 3.2.1 -> 3.2.1.9005 (GitHub: cf20da9)`, the SpaDES.core#446 merge, and the
  site built. The dependency is now implicit: if `SpaDES.experiment` drops that `Remotes:`
  entry the workflows fall back to the released SpaDES.core, which lacks
  `moduleRmdToVignette()`. A SpaDES.core release carrying it removes the coupling.

- **A job could inherit an R library linked against system libraries the runner no
  longer has.** `setup-r-dependencies` caches `$R_LIBS_USER` under an exact key plus a
  bare restore-key (`<os>-<R version>-<arch>-<cache-version>-`), and an exact-key miss --
  which is every dependency change -- restores the most recent library any job saved in
  that pool. Nothing in that key describes the *system* libraries the compiled packages
  link against, so an `sf` built against GDAL 3.11 restored onto a runner carrying GDAL
  3.8 and failed at load with `libgdal.so.37: cannot open shared object file`, long after
  a clean-looking install (CBMutils#91, `ubuntu-latest (devel)`). `terra` escaped in the
  same job only because pak happened to want a newer version and rebuilt it: one poisoned
  library, two outcomes, decided by version coincidence. `install-spatial-deps` now
  reports the installed libraries as an `abi` output (`gdal<v>-geos<v>-proj<v>`, from
  `gdal-config`/`geos-config`/`pkg-config` -- the same tools the packages' configure
  scripts consult), and `setup-r-deps` appends it to the cache version, making the
  restore-key ABI-specific. Jobs still share libraries, but only with jobs built against
  the same geospatial stack. The suffix is empty for `system-deps: false` and on Windows
  (the libraries are bundled into the R binaries there), which leaves those keys
  byte-identical, so pure-R and Windows callers keep their existing caches. Bumping
  `cache-version` is no longer the remedy for an ABI mismatch; it remains for what
  automation cannot see. The ABI probes never fail a job -- an unavailable probe yields
  an empty ABI, which reproduces the previous cache behaviour rather than going red
  across the organisation. `setup-r-deps` also gained `cache-version` and `abi` outputs,
  so what a library was keyed under is assertable rather than inferred from logs.
  Covered by a new `spatial-abi` self-test job on all three platforms.

- **New `ecosystem-test.yaml` workflow.** `self-test` runs the actions against a
  two-line fixture package, which cannot answer "does the organisation still build?" --
  the fixture has one Import, while the real consumers have deep, partly-r-universe
  dependency graphs. This workflow checks out real packages (reproducible, SpaDES.core,
  LandR, quickPlot by default) and runs them through the actions at the branch under
  test, asserting that dependency resolution completes, the cache key is ABI-specific,
  and the installed spatial stack actually loads. Dispatch it, or add the
  `ecosystem-test` label to a PR, before merging a change to `setup-r-deps` or
  `install-spatial-deps`. It also runs one real `R CMD check` (reproducible by default)
  through the production path -- `setup-r-deps` then `check-r-package` -- because an
  install-only job cannot fail the way production fails: the CBMutils failure that
  prompted this work installed cleanly and went red at check time.

- **`testthat-module.yaml`'s temporary SpaDES.core@development step did not reliably
  install development.** `install-SpaDES` already installs SpaDES.core from `development`
  (pulled in via `SpaDES.experiment`'s `Remotes:`), so the Version this step asks for is
  usually the one already installed and
  `Require::Require("PredictiveEcology/SpaDES.core@development")` printed "No packages to
  install/update", leaving whatever was there. The spec is now `@development (HEAD)`, which
  CI confirmed installs from GitHub even when the Versions are equal (fireSense_SpreadFit
  run 34638223714: plain spec skipped, `(HEAD)` fetched the requested branch) -- a version
  bump is not what makes this work. Found when `pkgdown-module.yaml`, which carries the same
  step, failed its first test.

- **New reusable workflow `pkgdown-module.yaml`**, which builds a pkgdown site for a SpaDES
  module and deploys it to `gh-pages`. A module is not a package, so it builds from the
  package rendition `SpaDES.core::convertToPackage(destinationPath = )` makes in a
  throwaway directory (as `testthat-module.yaml` does), turns `<module>.Rmd` into an
  article with `SpaDES.core::moduleRmdToVignette()`, installs the rendition -- pkgdown
  builds from an installed package, and `build_site(install = FALSE)` otherwise stops with
  "there is no package called ..." -- and runs `build_site_github_pages()`. Setup is
  `render-module-rmd.yaml`'s; build and deploy are separate jobs, so the write-scoped token
  never shares a job with the module's code. The `url` input sets a custom domain. Carries a
  temporary SpaDES.core@development step. `examples/pkgdown-module.caller.yaml` shows the
  call site. See PredictiveEcology/SpaDES-modules#40.

- **`test-coverage.yaml` uploads with `codecov/codecov-action@v7`, not `covr::codecov()`.**
  covr posts to Codecov's legacy `/upload/v2` endpoint, which only recognises
  per-repository upload tokens. Given the organisation's global upload token it answers
  404 ("Could not find a repository associated with upload token") and the step still
  passes, so a repository with no token of its own (fireSenseUtils) had green coverage
  runs that uploaded nothing. The R step now writes `cobertura.xml` with
  `covr::to_cobertura()`, and a separate step uploads it with
  `slug: ${{ github.repository }}`, which works with either kind of token.

  A failed upload now **fails the job**, except on a pull request that GitHub gives no
  secrets (a fork, Dependabot). Callers must pass `CODECOV_TOKEN` (or use
  `secrets: inherit`): Codecov no longer accepts tokenless uploads for PredictiveEcology.
  The token is now handed only to the upload step, not exported to every step of the job.

- **New reusable workflow `testthat-module.yaml`**, for running a SpaDES module's
  testthat suite. It is `render-module-rmd.yaml` with the render and commit jobs
  replaced by a test run; everything above them -- spatial system deps, the apt retry
  wrapper, `install-Require`, `install-SpaDES`, and dependency resolution straight from
  the module's own `reqdPkgs` via `SpaDES.core::packages()` -- is deliberately
  identical, so a fix to one is a fix to both. There is **no commit job**, and that
  omission is load-bearing: the workflow runs `convertToPackage()`, which rewrites a
  module and is not reversible, so nothing it produces may be pushed back.

  Three decisions worth knowing:

  * **The module is tested as a package.** A module keeps its functions inline in
    `<module>.R`, so without conversion they are only ever parsed into a `simList` and
    a test cannot call one directly. `convertToPackage(destinationPath = )` builds the
    package rendition in a throwaway directory -- the module itself is untouched -- and
    the tests then run against a real namespace, so `expect_equal(myHelper(3L), 6L)`
    works as it would in any package.
  * **A module with no tests does not fail.** Almost every module currently carries
    only the dead `newModule()` scaffolding; failing hard would paint the family red
    for the absence of tests rather than for a defect. The workflow reports "no tests"
    in the job summary and passes.
  * **Coverage goes to the job summary, not codecov.** ~28 modules with near-zero tests
    would create 28 projects reading 0-5% with no history for the `target: auto` ratchet
    to compare against, and module repositories have no `codecov.yml`. This is a choice,
    not a missing credential: the org-level `CODECOV_TOKEN` reaches module repositories,
    so uploading later needs only the secret declared and an upload step like
    `test-coverage.yaml`'s. `SpaDES.core::moduleCoverage()` reports against `<module>.R`
    rather than the generated `R/` copy. See PredictiveEcology/SpaDES.core#441.

  Carries a **temporary** step installing `PredictiveEcology/SpaDES.core@development`:
  `install-SpaDES` installs the released SpaDES.core, which does not yet have
  `convertToPackage(destinationPath = )` or `moduleCoverage()`. Drop it once a release
  carries both.

  Installs the test toolchain (`covr`, `pkgload`, `roxygen2`, `testthat`, `withr`)
  explicitly. All five are only in SpaDES.core's Suggests, so `install-SpaDES` does not
  provide them.

  `examples/testthat-module.caller.yaml` shows the call site;
  `examples/module-tests-setup.R` is a starting `tests/testthat/setup.R` for a module.

- **`revdeps-check`: two of its three inputs never worked, and the two steps
  disagreed about what they were checking.** All verified in R, not by reading:

  ```r
  isTRUE("true")                     #> FALSE  -- for every string, always
  as.difftime("30", units = "mins")  #> NA mins
  ```

  * `cranonly` was read with `isTRUE("${{ inputs.cranonly }}")`, which is `FALSE`
    for every value the template can produce. The CRAN-only branch was
    unreachable and the `else` branch always ran. Not a harmless no-op: the
    crancache key *does* interpolate `inputs.cranonly`, so setting it bought a
    separate cache namespace holding an identical revdep set. Now
    `isTRUE(as.logical(...))`.
  * `timeout` was passed to `revdep_check()` through
    `as.difftime("30", units = "mins")`. `as.difftime()` parses a character with
    `strptime(format = "%X")`, so `"30"` is not a time of day and `NA` -- no
    timeout at all -- is what has always been passed, in an action whose own
    README calls these checks "too resource intensive for standard GitHub
    runners". Now `as.numeric()` first.
  * The *Check reverse dependencies* step recomputed the revdep set
    unconditionally from `revdepcheck.extras`, ignoring `cranonly` entirely, so
    fixing the first bug alone would have populated the cache with one set and
    checked another. The crancache step now writes the list it actually used to
    `$RUNNER_TEMP/revdeps.txt` and the check step reads it.
  * `pak::pkg_install()` was called without pak necessarily being present.
    `r-lib/actions/setup-r-dependencies` leaves it on the path, which is why the
    `revdeps.yaml` reusable workflow was unaffected, but the README's standalone
    usage (plain `setup-r`) does not. Installed on demand now.

  Found in the review behind the withdrawn #29, which proposed deleting the
  action as unused. That is no longer true: `revdeps.yaml` wraps it and quickPlot
  calls that weekly, so the bugs were fixed rather than the action removed.

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

