# setup-r-deps

Installs an R package's dependencies the PredictiveEcology way: pandoc,
geospatial system libraries, R itself, and the dependency install with a retry
fallback.

Extracted from the `R-CMD-check` reusable workflow so a job that is **not**
running `R CMD check` can reuse it — a benchmark, an ad-hoc matrix leg, a
coverage run with different flags. Previously that meant copy-pasting ~90 lines.

## Usage

```yaml
- uses: actions/checkout@v7
- uses: PredictiveEcology/actions/setup-r-deps@main
  with:
    r-version: release
    extra-packages: any::rcmdcheck
```

Use `@main` — see [Which ref to use](../README.md#which-ref-to-use) in the repo README.

## Inputs

| input | default | notes |
| --- | --- | --- |
| `r-version` | `release` | passed to `setup-r` |
| `dependencies` | `"all"` | R expression for `setup-r-dependencies` |
| `extra-packages` | `""` | newline-separated, appended |
| `pak-version` | `stable` | devel occasionally regresses |
| `cache-version` | `1` | rarely needed; the geospatial ABI is appended automatically (see [Cache keys and the geospatial ABI](#cache-keys-and-the-geospatial-abi)) |
| `extra-repositories` | `""` | r-universe serves dev versions; opt in deliberately |
| `use-public-rspm` | `true` | Posit binaries |
| `ncpus` | `2` | |
| `pandoc` | `true` | set `false` for jobs that never render |
| `system-deps` | `true` | set `false` for a pure-R package |
| `post-install` | `""` | Rscript run after the install |
| `working-directory` | `.` | where DESCRIPTION lives |

## On timeouts

Composite-action steps do **not** support `timeout-minutes`
([actions/runner#1979](https://github.com/actions/runner/issues/1979)), and it
is not honoured on the step that *calls* a composite action either. The apt
steps are bounded with GNU `timeout` inside the `run:` block instead, which also
gives a per-command cap rather than one cap for the whole step. The dependency
retry uses `nick-fields/retry`, whose own `timeout_minutes` does work — composite
actions may `uses:` other actions.

## Cache keys and the geospatial ABI

`setup-r-dependencies` caches `$R_LIBS_USER` under an exact key plus a **bare
restore-key**:

```
key:          <os>-<R version>-<arch>-<cache-version>-<hash of dependency set>
restore-keys: <os>-<R version>-<arch>-<cache-version>-
```

An exact-key miss happens whenever the dependency set changes — i.e. routinely —
and the restore-key then matches the most recent library *any* job saved in that
pool. pak treats what it finds as installed and does not rebuild it.

Nothing in that key describes the **system** libraries the compiled packages are
linked against. A library built when the runner had a different GDAL restores
cleanly and fails much later, at load:

```
unable to load shared object '.../sf/libs/sf.so':
libgdal.so.37: cannot open shared object file: No such file or directory
```

So this action appends the ABI reported by `install-spatial-deps` to
`cache-version`, making the restore-key ABI-specific. Sharing a library between
jobs still happens — that is the cache earning its keep — but only between jobs
built against the same geospatial libraries.

The suffix is empty when `system-deps: false` and on Windows (where the
libraries are bundled into the R binaries, so there is no system ABI to drift
against). An empty suffix leaves the key byte-identical to before, so those
callers keep their existing caches.

You therefore should not need `cache-version` for an ABI mismatch any more. It
remains for what automation cannot see — a bad build from a compiler change, a
corrupt upload — and for namespacing a cache away from other callers.
