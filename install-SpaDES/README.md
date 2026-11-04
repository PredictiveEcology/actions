# install-SpaDES

This action installs quickPlot, reproducible, SpaDES.core and SpaDES.tools from CRAN
(what the archived `SpaDES` metapackage pulled in), then the development branches of:

- `PredictiveEcology/reproducible@development`
- `PredictiveEcology/SpaDES.core@development`

Note that this action requires the packages `remotes` and `Require` to be installed,
which can be done via the [`install-Require`](https://github.com/PredictiveEcology/actions/tree/main/install-Require)
action.

# Usage

Inputs available

- `upgrade` - default `TRUE`. A boolean passed to `Require::Require(..., upgrade)`

Basic:
```yaml
steps:
- uses: actions/checkout@v3
- uses: r-lib/actions/setup-r@v2
- uses: PredictiveEcology/actions/install-Require@v0
- uses: PredictiveEcology/actions/install-SpaDES@v0
```

# License

The scripts and documentation in this project are released under the [MIT License](LICENSE)

# Contributions

Contributions are welcome!
