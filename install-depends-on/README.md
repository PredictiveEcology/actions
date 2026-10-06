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

# Permissions

Public repositories need nothing beyond the default token. A private repository
needs `pull-requests: read` (the step reads the PR description); without it the
step warns and does nothing. Reading and installing a referenced PR in another
private repository needs a token that can read it, passed as `token:`.

# License

The scripts and documentation in this project are released under the [MIT License](LICENSE)
