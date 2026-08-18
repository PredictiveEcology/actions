# PredictiveEcology/actions (v0.4)

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

