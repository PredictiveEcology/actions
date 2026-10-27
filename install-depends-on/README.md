# install-depends-on

Tests a pull request against the unmerged code of another pull request it needs.
Opt-in: with no `Depends-on:` line, or on any event other than `pull_request`,
the step does nothing.

# Usage

Put one line per pull request in the PR description (body), anywhere:

```
Depends-on: PredictiveEcology/LandR#264
```

Matching is case-insensitive and ignores spaces around the line and after the
colon. Nothing else in the description triggers anything.

- The description is read through the GitHub API when the step runs, so editing
  it and re-running the job picks up the change.
- A referenced PR that is merged or closed is skipped, with a log line. Once the
  upstream merges, the stale line has no effect.
- Each open PR is installed with `pak::pkg_install("owner/repo#N", upgrade = TRUE)`
  after the normal dependency install, so it overrides the development version.
- A reference to the repository the PR is in is skipped, with a log line. A PR
  stacked on another PR of the same repository is branched from it and carries
  `Depends-on: owner/samerepo#N`; the parent's commits are already in the branch
  under test, so nothing is installed.
- Resolution is not transitive: list every PR the change needs.
- The log and the job summary show what was installed, e.g.
  `Depends-on: installed PredictiveEcology/LandR#264 -> LandR 1.2.0.9046 (sha a110a43)`.

The reusable workflows `R-CMD-check`, `test-coverage`, `testthat-module`,
`render-module-rmd`, `pkgdown` and `pkgdown-module` already call it; callers edit
nothing. To use it in your own workflow, add it after the dependency install:

```yaml
- uses: PredictiveEcology/actions/install-depends-on@main
```

# Modes

`mode:` picks the job; the default, `install`, is everything described above.

- `prepare`: run before the dependency solve. Downloads the head of each open upstream
  PR, adds one to the last component of its `DESCRIPTION` `Version` in that copy only
  (the post-merge bump), and returns `extra-packages` (the input plus one `local::<dir>`
  line per upstream) for `setup-r-dependencies`. The solver then meets a floor written as
  the post-merge version and tests the unmerged code. `preinstall: true` also installs
  the copies, for module workflows that resolve through Require. `install` mode afterwards
  installs the same bumped copies, so the version never drops below the floor. The
  upstream that is a SpaDES module (no `DESCRIPTION` at its root) is skipped with a
  note in the summary, since there is nothing to install; the `gate` still waits on its checks.
- `gate`: outputs `ready` (`false` while an upstream PR has pending or failed checks at its
  head, with `waiting for owner/repo#N (pending|failed)` in the job summary) and, with
  `reduced-matrix: true`, `config`, three release legs while an upstream is open. Without a
  `Depends-on:` line, or on a push, it finishes without installing R. An API error warns
  and reports ready. `hold: false` computes `config` only. A check run named
  `...depends-on-gate` is not counted as evidence, so an upstream that is itself waiting is
  pending, not green.
- `rerun`: re-runs the repository's finished PR runs whose jobs, apart from the gate, were
  all skipped, when every upstream is ready. Called by `depends-on-rerun.yaml`; needs
  `actions: write`.

The reusable workflows switch these on with `depends-on-virtual-bump`,
`depends-on-gate` and `depends-on-reduced-matrix` (all default `false`); see the
top-level README.

# Permissions

Public repositories need nothing beyond the default token. A private repository
needs `pull-requests: read` (the step reads the PR description); without it the
step warns and does nothing. Reading and installing a referenced PR in another
private repository needs a token that can read it, passed as `token:`.

# License

The scripts and documentation in this project are released under the [MIT License](LICENSE)
