# install-spatial-deps

This action runs reverse dependency checks for R packages.

# Usage

Inputs available

- `quiet` - default `true`. Logical. Suppress output from internal processes?
- `timeout` - default `1800`. Integer. Maximum time to wait (in seconds) for R CMD check to complete.

```yaml
steps:
  - uses: actions/checkout@v3
  - uses: PredictiveEcology/actions/install-spatial-deps@main
  - uses: r-lib/actions/setup-r@v2
      with:
        extra-repositories: https://predictiveecology.r-universe.dev
        Ncpus: 2
        r-version: ${{ matrix.config.r }}
        use-public-rspm: false
  - uses: PredictiveEcology/actions/revdeps-check@main
    with:
      quiet: true
      timeout: 1800
```

# License

The scripts and documentation in this project are released under the [MIT License](LICENSE)

# Contributions

Contributions are welcome!
