# install-spatial-deps

This action installs additional system dependencies for geospatial packages on Linux and macOS.

# Why this action still exists

`setup-r-deps` installs these same libraries — by delegating to this action —
so it is fair to ask whether this one is now redundant. It is not.

The SpaDES **module** repositories cannot go through the package path. A module
repo has no `DESCRIPTION`: its dependencies are declared inside
`defineModule(reqdPkgs = ...)`, so there is nothing for pak or
`setup-r-dependencies` to resolve against, and modules install their
dependencies with `Require::Require()` instead. Nothing on that path installs
system libraries — `Require`'s `.onLoad` deliberately sets `PKG_SYSREQS=false`
and `PKG_SYSREQS_SUDO=false`, because CRAN treats a package that shells out to
`sudo` on the user's machine as machine hijacking.

So on a module repo's CI, GDAL/GEOS/PROJ arrive from this action or not at all.
`setup-r-deps` covers the package repositories; this action covers the module
repositories and the standalone consumers.

# Usage

Basic:

```yaml
steps:
- uses: actions/checkout@v3
- uses: PredictiveEcology/actions/install-spatial-deps@main
- uses: r-lib/actions/setup-r@v2
```

# License

The scripts and documentation in this project are released under the [MIT License](LICENSE)

# Contributions

Contributions are welcome!
