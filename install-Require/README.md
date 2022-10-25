# install-Require

This action installs `remotes` and `Require` R packages the current R environment

# Usage

Inputs available

- `GitTag` - default `"master"`. A character indicating the branch, commit SHA or tag to append to "PredictiveEcology/Require@".
  Defaults to the master branch.

Basic:
```yaml
steps:
- uses: actions/checkout@v2
- uses: r-lib/actions/setup-r@v2
- uses: PredictiveEcology/actions/install-Require@v0
  with:
    GitTag: 'development'
```

# License

The scripts and documentation in this project are released under the [MIT License](LICENSE)

# Contributions

Contributions are welcome!