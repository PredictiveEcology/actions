# install-spatial-deps

This action installs additional system dependencies for geospatial packages on Linux and macOS.

# Usage

Basic:

```yaml
steps:
- uses: actions/checkout@v3
- uses: PredictiveEcology/actions/install-spatial-deps@main
- uses: r-lib/actions/setup-r@v2
```

# Outputs

| output | description |
| --- | --- |
| `abi` | the installed geospatial libraries, as `gdal<v>-geos<v>-proj<v>` |

`abi` identifies what compiled R packages in this job will link against. It is
empty on Windows, where the geospatial libraries are bundled into the R binaries
rather than provided by the system, so there is no system ABI to drift against.

Use it in the cache key of anything you build against these libraries. A package
binary records the GDAL soname it needs, and nothing about that appears in the
package version, the R version or the OS label — so a cache keyed on those alone
can restore a library that cannot load. `setup-r-deps` does this; see
[Cache keys and the geospatial ABI](../setup-r-deps/README.md#cache-keys-and-the-geospatial-abi).

```yaml
- uses: PredictiveEcology/actions/install-spatial-deps@main
  id: spatial
- uses: actions/cache@v4
  with:
    path: ~/R/library
    key: ${{ runner.os }}-${{ steps.spatial.outputs.abi }}-${{ hashFiles('DESCRIPTION') }}
```

# License

The scripts and documentation in this project are released under the [MIT License](LICENSE)

# Contributions

Contributions are welcome!
