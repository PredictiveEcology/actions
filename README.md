# actions

Collection of GitHub Actions workflows used by the Predictive Ecology group to
test packages, `SpaDES` modules, and render `SpaDES` module manuals.

# Which ref to use

**Use `@main`.** That is what every caller in this organisation is on, and it is
what these actions are tested against.

This reverses earlier advice in this file, which recommended a version tag or a
pinned SHA on the grounds that tags can move. The reasoning was sound in the
abstract and wrong in practice here: a pin does not freeze *correct* behaviour,
it freezes whatever was true on the day, including the bugs and including the
parts of the outside world the action reaches for.

The concrete case. Every published tag — `v0.1` through `v0.5` — still has
`install-spatial-deps` adding the `ubuntugis-unstable` PPA, which installs a GDAL
that is ABI-incompatible with the Posit binaries the R packages are built against
on `noble`. `main` dropped that PPA. A caller pinned to a tag for stability gets a
broken geospatial toolchain and no way to notice; that is what took quickPlot's
`revdeps` workflow out of service.

Pins also rot silently in a second way: they are the reason `v0.1`-`v0.5` cannot
be retired. Seventy-four module repositories still reference them.

`@main` moves, and that is the point — fixes reach callers. It is not unguarded:
`self-test.yaml` exercises the composite actions on every push and pull request,
and the reusable workflows are used by this organisation's own packages, so a
break surfaces immediately rather than at the next release.

Pin a SHA only when you have a specific reason to hold a version, and expect to
revisit it.

See [NEWS.md](https://github.com/PredictiveEcology/actions/blob/main/NEWS.md) for
the changes at each tag.

# Reusable workflows

These are the primary interface. A caller supplies its triggers and any
overrides; the matrix, system dependencies, caching and pins live here. See each
file's header comment for its inputs.

| workflow | what it does |
| --- | --- |
| `R-CMD-check.yaml` | the check matrix, incl. a `_R_CHECK_DEPENDS_ONLY_` leg |
| `test-coverage.yaml` | covr + codecov upload |
| `test-downstream.yaml` | check downstream packages against the branch under test |
| `pkgdown.yaml` | build the site and deploy to `gh-pages` |
| `revdeps.yaml` | reverse dependency checks (wraps `revdeps-check`) |
| `citation.yaml` | regenerate `CITATION.cff` from `DESCRIPTION` |
| `render-module-rmd.yaml` | render a SpaDES module's `.Rmd` and commit the result |

```yaml
jobs:
  R-CMD-check:
    uses: PredictiveEcology/actions/.github/workflows/R-CMD-check.yaml@main
    secrets: inherit
```

# Composite actions

The building blocks the workflows above are made of. Use them directly only when
no reusable workflow fits. For details and example usage see each action's
`README`.

1. [install-Require](https://github.com/PredictiveEcology/actions/tree/main/install-Require) - installs `Require` (and `remotes`);
1. [install-Rmd-pkgs](https://github.com/PredictiveEcology/actions/tree/main/install-Rmd-pkgs) - installs packages commonly needed to render SpaDES module manuals;
1. [install-SpaDES](https://github.com/PredictiveEcology/actions/tree/main/install-SpaDES) - installs `SpaDES` packages;
1. [install-spatial-deps](https://github.com/PredictiveEcology/actions/tree/main/install-spatial-deps) - system dependencies for geospatial packages on Ubuntu Linux and macOS;
1. [setup-r-deps](https://github.com/PredictiveEcology/actions/tree/main/setup-r-deps) - R, pandoc, system deps and the package dependency cache in one step;
1. [stage-gdrive-auth](https://github.com/PredictiveEcology/actions/tree/main/stage-gdrive-auth) - stage a Google Drive credential for tests that need one;
1. [revdeps-check](https://github.com/PredictiveEcology/actions/tree/main/revdeps-check) - run reverse dependency checks for R packages;

# More information on GitHub Actions

<https://github.com/r-lib/actions>

