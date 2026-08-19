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

