# install-Rmd-pkgs

This action installs packages that are usually necessary to render LandR module 
manuals (.Rmds). 

Some manual .Rmds may require additional packages which 
will need to be installed separately, unless they become shared across many modules
in which case they should be added to this action.

Note that this action requires the packages `remotes` and `Require` to be installed,
which can be done via the [`install-Require`](https://github.com/PredictiveEcology/actions/tree/main/install-Require)
action. That ordering is not optional and cannot be declared by the action
itself: `Require::setLinuxBinaryRepo()` is the first statement this action
runs, so without `install-Require` earlier **in the same job** it fails with
"there is no package called 'Require'".

# Usage

Inputs available

- `upgrade` - default `TRUE`. A boolean passed to `Require::Require(..., upgrade)`

Basic:
```yaml
steps:
- uses: actions/checkout@v7
- uses: r-lib/actions/setup-r@v2
- uses: PredictiveEcology/actions/install-Require@main
- uses: PredictiveEcology/actions/install-Rmd-pkgs@main
```

# License

The scripts and documentation in this project are released under the [MIT License](LICENSE)

# Contributions

Contributions are welcome!
