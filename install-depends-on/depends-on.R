## Install the open pull requests named by `Depends-on:` lines in the
## description of the pull request under test. See README.md in this directory.
##
## The parser and the skip rule are plain functions so tests/depends-on-test.R
## can source this file; `main()` runs only when the file is run as a script.

## One line, anywhere in the body: `Depends-on: owner/repo#123`.
depends_on_pattern <-
  "^\\s*Depends-on:\\s*([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#([0-9]+)\\s*$"

## Returns a data.frame(repo, number, ref) of the distinct references, in order.
parse_depends_on <- function(body) {
  body <- if (length(body) == 0 || is.na(body[1])) "" else paste(body, collapse = "\n")
  lines <- strsplit(body, "\r?\n")[[1]]
  m <- regmatches(lines, regexec(depends_on_pattern, lines, ignore.case = TRUE, perl = TRUE))
  m <- m[lengths(m) == 3]
  out <- data.frame(repo = vapply(m, `[`, "", 2), number = vapply(m, `[`, "", 3),
                    stringsAsFactors = FALSE)
  out$ref <- if (nrow(out)) paste0(out$repo, "#", out$number) else character()
  out[!duplicated(tolower(out$ref)), , drop = FALSE]
}

## A referenced PR is installed only while it is open and unmerged.
is_installable_pr <- function(state, merged_at) {
  identical(state, "open") && (is.na(merged_at) || !nzchar(merged_at))
}

## A reference to the repository under test is a stacked PR: its commits are
## already in the branch being tested, so installing it would fail (no DESCRIPTION
## in a module repo) or overwrite the code under test (a package repo).
is_same_repo <- function(dep_repo, repo) {
  identical(tolower(dep_repo), tolower(repo))
}

## `jq` must not contain double quotes: shQuote() is cmd-style on Windows runners.
gh_api <- function(path, jq) {
  out <- suppressWarnings(system2("gh", shQuote(c("api", path, "--jq", jq)), stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0) stop(paste(out, collapse = "\n"), call. = FALSE)
  out
}

main <- function() {
  event <- Sys.getenv("EVENT_NAME")
  if (event != "pull_request") {
    message("Depends-on: event is '", event, "', not pull_request; nothing to do.")
    return(invisible())
  }
  repo <- Sys.getenv("REPO")
  number <- Sys.getenv("PR_NUMBER")
  if (!nzchar(Sys.getenv("GITHUB_PAT"))) Sys.setenv(GITHUB_PAT = Sys.getenv("GH_TOKEN"))

  ## Read at run time, not from the event payload, so editing the description and
  ## re-running the job picks up the change. A failed read (e.g. a private repo
  ## whose caller did not grant `pull-requests: read`) must not break a PR that
  ## never asked for this, so it warns and does nothing.
  body <- tryCatch(paste(gh_api(sprintf("repos/%s/pulls/%s", repo, number), ".body"),
                         collapse = "\n"),
                   error = function(e) {
                     cat("::warning::Depends-on: could not read the description of ", repo, "#",
                         number, " (", conditionMessage(e), "); skipping.\n", sep = "")
                     NULL
                   })
  if (is.null(body)) return(invisible())

  deps <- parse_depends_on(body)
  if (nrow(deps) == 0) {
    message("Depends-on: no lines in the description; nothing to do.")
    return(invisible())
  }

  summary_lines <- "### Depends-on"
  for (i in seq_len(nrow(deps))) {
    ref <- deps$ref[i]
    if (is_same_repo(deps$repo[i], repo)) {
      msg <- sprintf("Depends-on: skipped %s (same repository: a stacked PR already contains it)", ref)
      message(msg)
      summary_lines <- c(summary_lines, paste0("- ", msg))
      next
    }
    info <- strsplit(gh_api(sprintf("repos/%s/pulls/%s", deps$repo[i], deps$number[i]),
                            "[.state, .merged_at] | @tsv"), "\t")[[1]]
    state <- info[1]
    merged_at <- if (length(info) > 1) info[2] else ""
    if (!is_installable_pr(state, merged_at)) {
      msg <- sprintf("Depends-on: skipped %s (%s); testing against its target branch as usual",
                     ref, if (nzchar(merged_at)) "merged" else state)
      message(msg)
      summary_lines <- c(summary_lines, paste0("- ", msg))
      next
    }
    if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
    cat("::group::Depends-on: installing ", ref, "\n", sep = "")
    res <- pak::pkg_install(ref, upgrade = TRUE, ask = FALSE)
    cat("::endgroup::\n")
    pkg <- res$package[res$direct][1]
    desc <- utils::packageDescription(pkg)
    sha <- if (is.null(desc$RemoteSha)) "unknown" else substr(desc$RemoteSha, 1, 7)
    msg <- sprintf("Depends-on: installed %s -> %s %s (sha %s)", ref, pkg, desc$Version, sha)
    message(msg)
    summary_lines <- c(summary_lines, paste0("- ", msg))
  }
  cat(summary_lines, file = Sys.getenv("GITHUB_STEP_SUMMARY"), sep = "\n", append = TRUE)
  invisible()
}

if (sys.nframe() == 0L) main()
