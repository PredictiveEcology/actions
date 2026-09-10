# install-Require

This action installs `remotes` and `Require` R packages the current R environment

# Usage

Inputs available

- `GitTag` - default `"development"`. A character indicating the branch, commit SHA
  or tag to append to `"PredictiveEcology/Require@"`.

Basic:
```yaml
steps:
- uses: actions/checkout@v7
- uses: r-lib/actions/setup-r@v2
- uses: PredictiveEcology/actions/install-Require@main
```

To install a ref other than the default:
```yaml
- uses: PredictiveEcology/actions/install-Require@main
  with:
    GitTag: 'main'
```

# License

The scripts and documentation in this project are released under the [MIT License](LICENSE)

# Contributions

Contributions are welcome!
