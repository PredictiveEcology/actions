# install-module-sysdeps

The Ubuntu system libraries that the SpaDES module workflows (`testthat-module`,
`render-module-rmd`, `pkgdown-module`) need, in one place. It calls
[install-apt-packages](../install-apt-packages), so installs are capped, retried and cached.
It includes the font and text-shaping libraries that `systemfonts` and `textshaping` need
when they build from source.

```yaml
steps:
- uses: PredictiveEcology/actions/install-module-sysdeps@main
  with:
    extra-apt: libnetcdf-dev   # optional
```

| input | description |
| --- | --- |
| `extra-apt` | further apt packages, whitespace-separated, installed in the same transaction |
