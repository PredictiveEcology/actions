## Template `tests/testthat/setup.R` for a SpaDES module.
##
## The module is converted to a package rendition before the tests run (see the
## testthat-module workflow), so the module's own functions are already in a real
## namespace: a test can call `myHelper(x)` directly rather than reaching into
## `sim@.xData$.mods$<module>$myHelper`.
##
## This file only sets options and makes a scratch directory. It deliberately does
## NOT install packages or download anything: dependency resolution happens once,
## before the tests, from the module's own `reqdPkgs` metadata.

withr::local_options(
  list(
    reproducible.useMemoise = TRUE,
    reproducible.verbose    = -2,
    Require.verbose         = -2,
    spades.moduleCodeChecks = FALSE,
    spades.moduleDocument   = FALSE,
    spades.useRequire       = FALSE
  ),
  .local_envir = testthat::teardown_env()
)

## A scratch tree that is removed when the suite finishes. Use `testPaths$outputs`
## etc. from a test rather than writing beside the module.
testPaths <- local({
  root <- withr::local_tempdir(.local_envir = testthat::teardown_env())
  paths <- list(
    cachePath  = file.path(root, "cache"),
    inputPath  = file.path(root, "inputs"),
    modulePath = normalizePath("..", winslash = "/", mustWork = FALSE),
    outputPath = file.path(root, "outputs")
  )
  for (p in paths) dir.create(p, recursive = TRUE, showWarnings = FALSE)
  paths
})
