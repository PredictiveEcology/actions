# install-Require

This action installs the `remotes` and `Require` R packages into the current R
environment.

# Usage

Inputs available

- `GitTag` - default `"development"`. A character indicating the branch, commit
  SHA or tag to append to `"PredictiveEcology/Require@"`.

  The default used to be documented (and implemented) as `"master"`.
  `PredictiveEcology/Require` has no `master` branch and no `master` tag —
  `git ls-remote` lists neither — so that default resolved to a hard
  `remotes::install_github()` failure for anyone who took it. `development` is
  the branch the org actually installs from.

Basic:
```yaml
steps:
- uses: actions/checkout@v7
- uses: r-lib/actions/setup-r@v2
- uses: PredictiveEcology/actions/install-Require@main
```

With an explicit ref:
```yaml
- uses: PredictiveEcology/actions/install-Require@main
  with:
    GitTag: 'main'
```

Run this **before** [`install-Rmd-pkgs`](../install-Rmd-pkgs) and
[`install-SpaDES`](../install-SpaDES): both open with
`Require::setLinuxBinaryRepo()` and fail with "there is no package called
'Require'" if it has not run first, in the same job.

# License

The scripts and documentation in this project are released under the [MIT License](LICENSE)

# Contributions

Contributions are welcome!
