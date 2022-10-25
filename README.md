# actions

Collection of GitHub Actions workflows used by the Predictive Ecology group to
test SpaDES modules and render their manual .Rmd files.

# News
`v0`
- Initial release of 3 actions: install-Require, install-Rmd-pkgs and install-SpaDES.

# Releases and tags

We use major version tags to mark breaking changes in these actions. For the 
current version, please use the v0 tag, e.g.:

```yaml
- uses: PredictiveEcology/actions/install-SpaDES@v0
```

The v0 tag occasionally changes, to introduce non-breaking fixes and improvements. 
These changes use more fine-grained tags, e.g. v0.1. You can refer to these as 
well in your workflow files if you need to.

# List of actions

1. [PredictiveEcology/actions/install-Require](https://github.com/PredictiveEcology/actions/tree/v2/install-Require) - Installs `Require` (and `remotes`)
1. [PredictiveEcology/actions/install-Rmd-pkgs](https://github.com/PredictiveEcology/actions/tree/v2/install-Rmd-pkgs) - Installs packages commonly needed to render SpaDES modules .Rmds (i.e. module manuals)
1. [PredictiveEcology/actions/install-SpaDES](https://github.com/PredictiveEcology/actions/tree/v2/install-SpaDES) - Installs SpaDES packages

# More information on GitHub Actions
https://github.com/PredictiveEcology/actions/tree/v2
