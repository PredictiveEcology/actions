## options and revdeps
options(revdepcheck.num_workers = getOption("Ncpus", 2L))

omit_pkgs <- c(
  "SpaDES.project" ## omit b/c it circularly Suggests SpaDES.config
)
revdeps <- c(
  revdepcheck.extras::revdep_children(),
  revdepcheck.extras::revdep_grandchildren()
) |>
  setdiff(omit_pkgs)

## setup and run the checks
revdepcheck.extras::revdep_init()
revdepcheck::revdep_add(packages = revdeps)

revdepcheck::revdep_check(
  num_workers = getOption("revdepcheck.num_workers", 2L),
  quiet = as.logical("${{ inputs.quiet }}"),
  timeout = as.difftime("${{ inputs.timeout }}", units = "mins")
)

revdepcheck::revdep_report(all = TRUE)
