# install-SpaDES

This action installs SpaDES packages via the `SpaDES` metapackage. It also
installs SpaDES packages not currently on CRAN, notably:

- `PredictiveEcology/SpaDES.experiment@development`

**The `SpaDES` metapackage is currently archived on CRAN** (2026-07-13,
"requires archived package 'reproducible'"), so the CRAN repository alone
cannot satisfy `Require::Require("SpaDES")`. Add the org's r-universe to the
repositories before calling this action; `Require::setLinuxBinaryRepo()`
inserts Posit's binary repo *before* the CRAN mirror and preserves the rest of
`getOption("repos")`, so the entry survives into the action.

Note that this action requires the packages `remotes` and `Require` to be installed,
which can be done via the [`install-Require`](https://github.com/PredictiveEcology/actions/tree/main/install-Require)
action. That ordering is not optional and cannot be declared by the action
itself: `Require::setLinuxBinaryRepo()` is the first statement this action
runs, so without `install-Require` earlier **in the same job** it fails with
"there is no package called 'Require'".

# Usage

Inputs available

- `upgrade` - default `TRUE`. A boolean passed to `Require::Require(..., upgrade)`

Basic:
```yaml
steps:
- uses: actions/checkout@v7
- uses: r-lib/actions/setup-r@v2
  with:
    extra-repositories: https://predictiveecology.r-universe.dev
- uses: PredictiveEcology/actions/install-Require@main
- uses: PredictiveEcology/actions/install-SpaDES@main
```

# License

The scripts and documentation in this project are released under the [MIT License](LICENSE)

# Contributions

Contributions are welcome!
