# actions

Collection of GitHub Actions workflows used by the Predictive Ecology group to
test packages, `SpaDES` modules, and render `SpaDES` module manuals.

# Releases and tags

We use major version tags to mark breaking changes in these actions.
For the most recent current version use the `main` tag, although note that this is likely to change unexpectedly as we update this repo.
We recommend using a fixed, stable version of the actions, either by specifying a version tag (e.g., `v0.1`) or, even better, by specifying a specific git commit sha (because tags can be changed).

See [NEWS.md](https://github.com/PredictiveEcology/actions/blob/main/NEWS.md) for description of changes made at each version tag.

# List of actions

For details and example usage of each action, please see the corresponding action's `README` file.

1. [PredictiveEcology/actions/install-Require](https://github.com/PredictiveEcology/actions/tree/main/install-Require) - Installs `Require` (and `remotes`);
1. [PredictiveEcology/actions/install-Rmd-pkgs](https://github.com/PredictiveEcology/actions/tree/main/install-Rmd-pkgs) - Installs packages commonly needed to render SpaDES module manuals;
1. [PredictiveEcology/actions/install-SpaDES](https://github.com/PredictiveEcology/actions/tree/v0/install-SpaDES) - Installs `SpaDES` packages;
1. [PredictiveEcology/actions/install-spatial-deps](https://github.com/PredictiveEcology/actions/tree/main/install-spatial-deps) - installs additional system dependencies for geospatial packages on Ubuntu Linux and macOS;
1. [PredictiveEcology/actions/revdeps-check](https://github.com/PredictiveEcology/actions/tree/main/revdeps-check) - run reverse dependency checks for R packages;

# More information on GitHub Actions

<https://github.com/r-lib/actions>

