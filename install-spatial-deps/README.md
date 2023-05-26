# install-spatial-deps

This action installs additional system dependencies for geospatial packages on Linux and macOS.

# Usage

Basic:

```yaml
steps:
- uses: actions/checkout@v2
- uses: PredictiveEcology/actions/install-spatial-deps
- uses: r-lib/actions/setup-r@v2
```

# License

The scripts and documentation in this project are released under the [MIT License](LICENSE)

# Contributions

Contributions are welcome!