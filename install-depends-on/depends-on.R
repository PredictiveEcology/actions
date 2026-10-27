## Everything about `Depends-on:` lines in the description of the pull request
## under test. See README.md in this directory. `DEPENDS_ON_MODE` picks the job:
##
##   prepare  before the dependency solve: fetch each open upstream PR, add one to
##            the last component of its Version (the post-merge bump), and hand it
##            to the solver as `local::<dir>`.
##   install  after the dependency install: install those same copies.
##   gate     decide whether the upstream PRs are green; sets `ready`.
##   rerun    re-run this repository's runs that the gate skipped, once ready.
##
## The parser, the version bump and the decisions are plain functions so
## tests/depends-on-test.R can source this file; `main()` runs only when the file
## is run as a script.

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

## The workflow job that holds the gate. A check run named like this is the gate
## itself, not evidence that the PR's real jobs ran.
gate_job_id <- "depends-on-gate"

## Mirrors the post-merge bump: one added to the last numeric component, keeping
## the separators ("3.2.1.9071" -> "3.2.1.9072", "1.2-3" -> "1.2-4").
bump_version <- function(version) {
  m <- regmatches(version, regexec("^(.*[.-])?([0-9]+)$", version))[[1]]
  if (length(m) != 3) stop("cannot increment the version '", version, "'", call. = FALSE)
  paste0(m[2], format(as.numeric(m[3]) + 1, scientific = FALSE))
}

## The lines of a DESCRIPTION with only the Version value changed.
bump_description <- function(lines) {
  i <- grep("^Version:", lines)
  if (length(i) != 1) stop("DESCRIPTION needs exactly one Version field", call. = FALSE)
  lines[i] <- paste0("Version: ", bump_version(trimws(sub("^Version:", "", lines[i]))))
  lines
}

## State of an open upstream PR from its check runs at its head commit.
## Failed beats pending. A PR whose only success is the gate (its real jobs were
## skipped because it waits on something itself) is not green, and neither is one
## with no checks yet.
check_state <- function(name, status, conclusion) {
  keep <- !grepl(paste0(gate_job_id, "$"), name)
  status <- status[keep]; conclusion <- conclusion[keep]
  if (any(status == "completed" & conclusion %in%
          c("failure", "timed_out", "cancelled", "action_required", "startup_failure", "stale"))) {
    return("failed")
  }
  if (length(status) == 0 || any(status != "completed") || !any(conclusion == "success")) {
    return("pending")
  }
  "green"
}

## `states` is one of green, merged, closed, same-repo, no-checks, pending, failed
## per ref. An upstream with no checks at all is not waited for: nothing would ever
## turn it green.
gate_decision <- function(refs, states) {
  waiting <- states %in% c("pending", "failed")
  list(ready = !any(waiting),
       lines = c(sprintf("waiting for %s (%s)", refs[waiting], states[waiting]),
                 sprintf("%s has no checks; not waiting", refs[states == "no-checks"])))
}

## A finished run of the PR's head whose every job but the gate was skipped was
## held by the gate, and is worth re-running once the upstream is ready.
is_gated_run <- function(job_names, conclusions) {
  gate <- grepl(paste0(gate_job_id, "$"), job_names)
  any(gate) && any(!gate) && all(conclusions[!gate] == "skipped")
}

## While an upstream PR is still open, R-CMD-check runs only these legs: release on
## each OS. The full default matrix stays in R-CMD-check.yaml; the gate returns
## "" (use it) once no upstream is open, and on push events.
reduced_config <- function(states) {
  if (!any(states %in% c("green", "pending", "failed", "no-checks"))) return("")
  os <- c("ubuntu-latest", "windows-latest", "macOS-latest")
  paste0("[", paste(sprintf('{"os":"%s","nosuggests":false,"r":"release"}', os), collapse = ","), "]")
}

skip_message <- function(ref, status) {
  if (status == "same-repo") {
    sprintf("Depends-on: skipped %s (same repository: a stacked PR already contains it)", ref)
  } else {
    sprintf("Depends-on: skipped %s (%s); testing against its target branch as usual", ref, status)
  }
}


## `jq` must not contain double quotes: shQuote() is cmd-style on Windows runners.
gh_api <- function(path, jq, paginate = FALSE) {
  args <- c("api", if (paginate) "--paginate", path, "--jq", jq)
  out <- suppressWarnings(system2("gh", shQuote(args), stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0) stop(paste(out, collapse = "\n"), call. = FALSE)
  out
}

## `name = value` for later steps; a delimiter keeps multi-line values intact.
set_output <- function(name, value) {
  f <- Sys.getenv("GITHUB_OUTPUT")
  if (nzchar(f)) cat(sprintf("%s<<DEPENDS_ON_EOF\n%s\nDEPENDS_ON_EOF\n", name, value), file = f, append = TRUE)
}

add_summary <- function(lines) {
  f <- Sys.getenv("GITHUB_STEP_SUMMARY")
  if (nzchar(f)) cat(lines, file = f, sep = "\n", append = TRUE)
}

## The upstream PRs named in the description of `repo`#`number`, read at run time
## so editing the description and re-running picks up the change. A failed read
## (e.g. a private repo whose caller did not grant `pull-requests: read`) must not
## break a PR that never asked for this, so it warns and returns no references.
read_deps <- function(repo, number) {
  body <- tryCatch(paste(gh_api(sprintf("repos/%s/pulls/%s", repo, number), ".body"),
                         collapse = "\n"),
                   error = function(e) {
                     cat("::warning::Depends-on: could not read the description of ", repo, "#",
                         number, " (", conditionMessage(e), "); skipping.\n", sep = "")
                     ""
                   })
  parse_depends_on(body)
}

## One referenced PR: status is same-repo, closed, merged or open, plus its head.
resolve_dep <- function(dep_repo, number, repo) {
  if (is_same_repo(dep_repo, repo)) return(list(status = "same-repo", sha = ""))
  info <- strsplit(gh_api(sprintf("repos/%s/pulls/%s", dep_repo, number),
                          "[.state, .merged_at, .head.sha] | @tsv"), "\t")[[1]]
  state <- info[1]
  merged_at <- if (length(info) > 2) info[2] else ""
  status <- if (is_installable_pr(state, merged_at)) "open" else if (nzchar(merged_at)) "merged" else state
  list(status = status, sha = info[length(info)])
}

depends_on_dir <- function() {
  root <- Sys.getenv("RUNNER_TEMP")
  file.path(if (nzchar(root)) root else tempdir(), "depends-on")
}

## The head of an open upstream PR as a local package with its Version bumped,
## fetched once per job: prepare and install must hand the solver the same copy.
## NULL when the repository is a SpaDES module (no DESCRIPTION at its root): there
## is nothing to install, and the gate still waits on its checks.
fetch_bumped_package <- function(dep_repo, number, sha) {
  base <- file.path(depends_on_dir(), paste0(gsub("/", "-", dep_repo), "-", number))
  pkg_dir <- file.path(base, "pkg")
  if (!file.exists(file.path(pkg_dir, "DESCRIPTION"))) {
    dir.create(base, recursive = TRUE, showWarnings = FALSE)
    tarball <- file.path(base, "head.tar.gz")
    token <- Sys.getenv("GH_TOKEN")
    utils::download.file(sprintf("https://api.github.com/repos/%s/tarball/%s", dep_repo, sha),
                         tarball, mode = "wb", quiet = TRUE, method = "libcurl",
                         headers = if (nzchar(token)) c(Authorization = paste("Bearer", token)))
    utils::untar(tarball, exdir = file.path(base, "untar"))
    top <- list.dirs(file.path(base, "untar"), recursive = FALSE)
    if (length(top) != 1 || !file.exists(file.path(top, "DESCRIPTION"))) {
      unlink(base, recursive = TRUE)
      return(NULL)
    }
    file.rename(top, pkg_dir)
    desc <- file.path(pkg_dir, "DESCRIPTION")
    writeLines(bump_description(readLines(desc)), desc)
    writeLines(sha, file.path(base, "sha"))
  }
  normalizePath(pkg_dir, winslash = "/")
}

install_pak <- function() if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")

## Open upstream PRs of the PR under test, resolved: a list of
## list(ref, repo, number, status, sha), plus the lines for the summary.
resolve_all <- function(deps, repo) {
  lapply(seq_len(nrow(deps)), function(i) {
    c(list(ref = deps$ref[i], repo = deps$repo[i], number = deps$number[i]),
      resolve_dep(deps$repo[i], deps$number[i], repo))
  })
}

prepare_or_install <- function(mode, repo, number) {
  extra <- Sys.getenv("INPUT_EXTRA_PACKAGES")
  deps <- read_deps(repo, number)
  if (nrow(deps) == 0) {
    message("Depends-on: no lines in the description; nothing to do.")
    if (mode == "prepare") set_output("extra-packages", extra)
    return(invisible())
  }
  summary_lines <- "### Depends-on"
  local_refs <- character()
  for (d in resolve_all(deps, repo)) {
    if (d$status != "open") {
      msg <- skip_message(d$ref, d$status)
    } else {
      dir <- fetch_bumped_package(d$repo, d$number, d$sha)
      if (is.null(dir)) {
        msg <- sprintf("Depends-on: skipped %s (a SpaDES module, not a package: nothing to install)", d$ref)
      } else {
        pkg <- read.dcf(file.path(dir, "DESCRIPTION"), "Package")[1]
        version <- read.dcf(file.path(dir, "DESCRIPTION"), "Version")[1]
        ref <- paste0("local::", dir)
        if (mode == "prepare") {
          local_refs <- c(local_refs, ref)
          msg <- sprintf("Depends-on: prepared %s -> %s %s (virtual bump of its head %s), for the dependency solve",
                         d$ref, pkg, version, substr(d$sha, 1, 7))
        } else {
          install_pak()
          cat("::group::Depends-on: installing ", d$ref, "\n", sep = "")
          pak::pkg_install(ref, upgrade = TRUE, ask = FALSE)
          cat("::endgroup::\n")
          msg <- sprintf("Depends-on: installed %s -> %s %s (sha %s)", d$ref, pkg, version,
                         substr(d$sha, 1, 7))
        }
      }
    }
    message(msg)
    summary_lines <- c(summary_lines, paste0("- ", msg))
  }
  if (mode == "prepare") {
    set_output("extra-packages", paste(c(extra, local_refs), collapse = "\n"))
    if (length(local_refs) && Sys.getenv("INPUT_PREINSTALL") == "true") {
      install_pak()
      pak::pkg_install(local_refs, upgrade = TRUE, ask = FALSE)
    }
  }
  add_summary(summary_lines)
  invisible()
}

## State of every upstream of a PR, as gate_decision() wants it.
upstream_states <- function(deps, repo) {
  vapply(resolve_all(deps, repo), function(d) {
    if (d$status != "open") return(d$status)
    cr <- strsplit(gh_api(sprintf("repos/%s/commits/%s/check-runs?per_page=100", d$repo, d$sha),
                          ".check_runs[] | [.name, .status, (.conclusion | tostring)] | @tsv",
                          paginate = TRUE), "\t")
    cr <- cr[lengths(cr) == 3]
    if (length(cr) == 0 &&
        identical(gh_api(sprintf("repos/%s/commits/%s/status", d$repo, d$sha), ".total_count"), "0")) {
      return("no-checks")
    }
    check_state(vapply(cr, `[`, "", 1), vapply(cr, `[`, "", 2), vapply(cr, `[`, "", 3))
  }, "")
}

## Fails open: an API error must not hold up a PR, so it warns and says ready.
run_gate <- function(repo, number) {
  ready <- tryCatch({
    deps <- read_deps(repo, number)
    if (nrow(deps) == 0) {
      TRUE
    } else {
      states <- upstream_states(deps, repo)
      d <- gate_decision(deps$ref, states)
      if (Sys.getenv("INPUT_REDUCED_MATRIX") == "true") set_output("config", reduced_config(states))
      add_summary(c("### Depends-on gate",
                    if (d$ready) c("All upstream pull requests are green, merged or closed: running.",
                                   paste0("- ", d$lines))
                    else paste0("- ", d$lines, "; the jobs are skipped until then.")))
      message(if (d$ready) "Depends-on gate: ready." else paste(d$lines, collapse = "; "))
      d$ready || Sys.getenv("INPUT_HOLD") != "true"
    }
  }, error = function(e) {
    cat("::warning::Depends-on gate: ", conditionMessage(e), "; running anyway.\n", sep = "")
    TRUE
  })
  set_output("ready", tolower(as.character(ready)))
}

## For every open PR of `repo` that names upstreams: when they are all ready,
## re-run its finished runs that the gate skipped.
run_rerun <- function(repo) {
  prs <- strsplit(gh_api(sprintf("repos/%s/pulls?state=open&per_page=100", repo),
                         ".[] | [.number, .head.sha] | @tsv", paginate = TRUE), "\t")
  summary_lines <- "### Depends-on re-run"
  for (pr in prs) {
    deps <- read_deps(repo, pr[1])
    if (nrow(deps) == 0) next
    runs <- strsplit(gh_api(sprintf("repos/%s/actions/runs?head_sha=%s&event=pull_request&per_page=100",
                                    repo, pr[2]),
                            ".workflow_runs[] | [.id, .status] | @tsv"), "\t")
    ids <- vapply(Filter(function(r) r[2] == "completed", runs), `[`, "", 1)
    gated <- Filter(function(id) {
      jobs <- strsplit(gh_api(sprintf("repos/%s/actions/runs/%s/jobs?filter=latest&per_page=100", repo, id),
                              ".jobs[] | [.name, (.conclusion | tostring)] | @tsv"), "\t")
      is_gated_run(vapply(jobs, `[`, "", 1), vapply(jobs, `[`, "", 2))
    }, ids)
    if (length(gated) == 0) next
    d <- gate_decision(deps$ref, upstream_states(deps, repo))
    msg <- if (d$ready) sprintf("PR #%s: upstream ready, re-running run(s) %s", pr[1], paste(gated, collapse = ", "))
           else sprintf("PR #%s: %s", pr[1], paste(d$lines, collapse = "; "))
    message(msg)
    summary_lines <- c(summary_lines, paste0("- ", msg))
    if (d$ready) for (id in gated) system2("gh", c("run", "rerun", id, "--repo", repo))
  }
  add_summary(summary_lines)
}

main <- function() {
  mode <- Sys.getenv("DEPENDS_ON_MODE", "install")
  repo <- Sys.getenv("REPO")
  if (!nzchar(Sys.getenv("GITHUB_PAT"))) Sys.setenv(GITHUB_PAT = Sys.getenv("GH_TOKEN"))
  if (mode == "rerun") return(run_rerun(repo))
  event <- Sys.getenv("EVENT_NAME")
  if (event != "pull_request") {
    message("Depends-on: event is '", event, "', not pull_request; nothing to do.")
    if (mode == "gate") { set_output("ready", "true"); set_output("config", "") }
    if (mode == "prepare") set_output("extra-packages", Sys.getenv("INPUT_EXTRA_PACKAGES"))
    return(invisible())
  }
  number <- Sys.getenv("PR_NUMBER")
  if (mode == "gate") run_gate(repo, number) else prepare_or_install(mode, repo, number)
}

if (sys.nframe() == 0L) main()
