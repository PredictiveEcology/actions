# install-Rmd-pkgs

This action installs packages that are usually necessary to render LandR module 
manuals (.Rmds). 

Some manual .Rmds may require aditional packages which 
will need to be installed separately, unless they become shared across many modules
in which case they should be added to this action.

Note that this action requires the packages `remotes` and `Require` to be installed,
which can be done via the [`install-Require`](https://github.com/PredictiveEcology/actions/tree/main/install-Require)
action.

# Usage

Inputs available

None at the moment.

Basic:
```yaml
steps:
- uses: actions/checkout@v2
- uses: r-lib/actions/setup-r@v2
- uses: PredictiveEcology/actions/install-Require@v0
- uses: PredictiveEcology/actions/install-Rmd-pkgs@v0
```

# License

The scripts and documentation in this project are released under the [MIT License](LICENSE)

# Contributions

Contributions are welcome!