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

## manual pre-installation (uses crancache)
crancache::update_packages(lib.loc = .libPaths()[1], ask = FALSE)
revdepcheck.extras::revdep_precache(pkgs = revdeps)

## sequentially install deps of each revdeps package in parallel;
## NOTE: PE pkgs aren't crancached, and will be installed each time.
if (Sys.info()[["sysname"]] == "Darwin") {
  fs::path("revdep", "library.noindex", revdeps) |> fs::dir_create()
} else {
  fs::path("revdep", "library", revdeps) |> fs::dir_create()
}
lapply(revdeps, revdepcheck:::deps_install, pkgdir = ".")
