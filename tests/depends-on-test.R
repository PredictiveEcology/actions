## Unit tests for install-depends-on/depends-on.R: the line parser, the skip rule, the
## virtual version bump, and the gate and re-run decisions. No network.
## Run: Rscript tests/depends-on-test.R
source("install-depends-on/depends-on.R")

eq <- function(got, want, what) {
  if (!identical(got, want)) {
    stop(what, ": got ", deparse(got), ", wanted ", deparse(want), call. = FALSE)
  }
  cat("ok:", what, "\n")
}
refs <- function(body) parse_depends_on(body)$ref

eq(refs("Depends-on: A/b#1"), "A/b#1", "plain line")
eq(refs("intro\n\ndepends-ON:   PredictiveEcology/LandR#264  \ntail"),
   "PredictiveEcology/LandR#264", "any position, case-insensitive, spaces")
eq(refs("  Depends-on:A/b.c-d_e#12\r\nDepends-on: X/y#3\r\n"), c("A/b.c-d_e#12", "X/y#3"),
   "CRLF, no space after colon, two lines")
eq(refs("Depends-on: A/b#1\ndepends-on: a/B#1"), "A/b#1", "duplicates dropped")
eq(refs(""), character(), "empty body")
eq(refs(NA_character_), character(), "NA body")
eq(refs(character()), character(), "no body")
eq(refs("No Depends-on: A/b#1 mid-line"), character(), "not at line start")
eq(refs("Depends-on: A/b#1 and more"), character(), "trailing text")
eq(refs("Depends-on: A/b#"), character(), "no number")
eq(refs("Depends-on: A#1"), character(), "no owner")
eq(refs("Depends-on: https://github.com/A/b/pull/1"), character(), "URL form not accepted")
eq(refs("Fixes A/b#1\nSee A/b#2"), character(), "other mentions ignored")

eq(is_installable_pr("open", ""), TRUE, "open, unmerged")
eq(is_installable_pr("open", NA_character_), TRUE, "open, NA merged_at")
eq(is_installable_pr("closed", ""), FALSE, "closed")
eq(is_installable_pr("closed", "2026-01-01T00:00:00Z"), FALSE, "merged")
eq(is_installable_pr("open", "2026-01-01T00:00:00Z"), FALSE, "merged_at wins")

eq(is_same_repo("PredictiveEcology/fireSense_spreadFit", "predictiveecology/FireSense_SpreadFit"), TRUE,
   "same repository, different case")
eq(is_same_repo("PredictiveEcology/LandR", "PredictiveEcology/fireSense_spreadFit"), FALSE,
   "other repository")

## Virtual bump: the post-merge version, last component plus one.
eq(bump_version("3.2.1.9071"), "3.2.1.9072", "dev version")
eq(bump_version("1.2-3"), "1.2-4", "dash separator")
eq(bump_version("1.0"), "1.1", "two components")
eq(bump_version("7"), "8", "one component")
eq(bump_version("1.0.99999"), "1.0.100000", "no scientific notation")
eq(tryCatch(bump_version("1.0.0-beta"), error = function(e) "error"), "error", "no numeric tail")
desc <- c("Package: reproducible", "Version: 3.2.1.9071", "Remotes: A/b@development",
          "Config/Version: 1")
eq(bump_description(desc),
   c("Package: reproducible", "Version: 3.2.1.9072", "Remotes: A/b@development", "Config/Version: 1"),
   "only the Version field changes")
eq(tryCatch(bump_description("Package: x"), error = function(e) "error"), "error", "no Version field")
## The point of the bump: a floor written as the post-merge version is met.
eq(package_version(bump_version("3.2.1.9071")) >= "3.2.1.9072", TRUE, "post-merge floor satisfied")

## Upstream state from check runs.
cs <- function(...) { x <- list(...); check_state(x$n, x$s, x$c) }
eq(cs(n = c("a", "b"), s = c("completed", "completed"), c = c("success", "skipped")), "green", "green")
eq(cs(n = c("a", "b"), s = c("completed", "in_progress"), c = c("success", "null")), "pending", "pending")
eq(cs(n = c("a", "b"), s = c("completed", "in_progress"), c = c("failure", "null")), "failed",
   "failed beats pending")
eq(cs(n = "a", s = "completed", c = "cancelled"), "failed", "cancelled is failed")
eq(cs(n = character(), s = character(), c = character()), "pending", "no checks yet")
eq(cs(n = c("x", "R-CMD-check / depends-on-gate", "R-CMD-check / mac"), s = rep("completed", 3),
      c = c("skipped", "success", "skipped")), "pending", "only the gate succeeded: upstream itself waits")
eq(cs(n = c("R-CMD-check / depends-on-gate", "R-CMD-check / mac"), s = rep("completed", 2),
      c = c("success", "success")), "green", "gate plus a real success")

## Gate decision.
g <- gate_decision(c("A/b#1", "C/d#2"), c("green", "merged"))
eq(g$ready, TRUE, "green and merged: ready")
eq(length(g$lines), 0L, "nothing to report when ready")
g <- gate_decision(c("A/b#1", "C/d#2", "E/f#3"), c("pending", "closed", "failed"))
eq(g$ready, FALSE, "pending and failed: not ready")
eq(g$lines, c("waiting for A/b#1 (pending)", "waiting for E/f#3 (failed)"), "summary lines")
eq(gate_decision(character(), character())$ready, TRUE, "no references: ready")
eq(gate_decision("A/b#1", "same-repo")$ready, TRUE, "stacked PR in the same repository: ready")

## Re-run: only a run whose every non-gate job was skipped.
eq(is_gated_run(c("R-CMD-check / depends-on-gate", "R-CMD-check / mac", "R-CMD-check / win"),
                c("success", "skipped", "skipped")), TRUE, "held by the gate")
eq(is_gated_run(c("R-CMD-check / depends-on-gate", "R-CMD-check / mac"), c("success", "success")),
   FALSE, "ran normally")
eq(is_gated_run(c("R-CMD-check / depends-on-gate", "R-CMD-check / mac"), c("success", "failure")),
   FALSE, "ran and failed")
eq(is_gated_run("R-CMD-check / mac", "skipped"), FALSE, "no gate job: not ours")
eq(is_gated_run("R-CMD-check / depends-on-gate", "success"), FALSE, "gate only")

eq(skip_message("A/b#1", "merged"),
   "Depends-on: skipped A/b#1 (merged); testing against its target branch as usual", "skip message")

## Matrix: three release legs while an upstream is open, the full default otherwise ("").
rc <- reduced_config(c("pending"))
eq(rc, '[{"os":"ubuntu-latest","nosuggests":false,"r":"release"},{"os":"windows-latest","nosuggests":false,"r":"release"},{"os":"macOS-latest","nosuggests":false,"r":"release"}]',
   "reduced matrix while the upstream is open")
eq(reduced_config("green"), rc, "green but still open: reduced")
eq(reduced_config(c("failed", "merged")), rc, "any open upstream: reduced")
eq(reduced_config(c("merged", "closed", "same-repo")), "", "all merged/closed: full matrix")
eq(reduced_config(character()), "", "no upstream: full matrix")

## An upstream with no checks at all is not waited for.
g <- gate_decision(c("A/b#1", "C/d#2"), c("no-checks", "green"))
eq(g$ready, TRUE, "no checks: ready")
eq(g$lines, "A/b#1 has no checks; not waiting", "no checks: summary line")
eq(gate_decision(c("A/b#1", "C/d#2"), c("no-checks", "pending"))$lines,
   c("waiting for C/d#2 (pending)", "A/b#1 has no checks; not waiting"), "no checks beside a pending one")
eq(reduced_config("no-checks") != "", TRUE, "no checks but still open: reduced matrix")

## Chains: the Depends-on lines of each open referenced PR are followed, deepest first.
fake <- function(graph, open = names(graph)) {
  calls <- character()
  list(read = function(repo, n) {
         calls <<- c(calls, paste0(repo, "#", n))
         parse_depends_on(graph[[tolower(paste0(repo, "#", n))]])
       },
       follow = function(repo, n) tolower(paste0(repo, "#", n)) %in% open,
       calls = function() calls)
}
chain <- function(f, repo = "T/t", n = "1") transitive_deps(repo, n, f$read, f$follow)$ref

f <- fake(list("t/t#1" = "Depends-on: A/a#2", "a/a#2" = "Depends-on: B/b#3", "b/b#3" = ""))
eq(chain(f), c("B/b#3", "A/a#2"), "2-level chain: deepest first")

f <- fake(list("t/t#1" = "Depends-on: A/a#2\nDepends-on: B/b#3", "a/a#2" = "Depends-on: C/c#4",
               "b/b#3" = "Depends-on: C/c#4", "c/c#4" = ""))
eq(chain(f), c("C/c#4", "A/a#2", "B/b#3"), "diamond: each reference once")
eq(sum(f$calls() == "C/c#4"), 1L, "diamond: shared PR read once")

f <- fake(list("t/t#1" = "Depends-on: A/a#2", "a/a#2" = "Depends-on: B/b#3",
               "b/b#3" = "Depends-on: A/a#2"))
eq(chain(f), c("B/b#3", "A/a#2"), "cycle terminates")

f <- fake(list("t/t#1" = "Depends-on: A/a#2", "a/a#2" = "Depends-on: t/T#1\nDepends-on: B/b#3",
               "b/b#3" = ""), open = c("a/a#2", "b/b#3"))
eq(chain(f), c("B/b#3", "A/a#2"), "reference back to the repo under test is skipped")

f <- fake(list("t/t#1" = "Depends-on: A/a#2", "a/a#2" = "Depends-on: B/b#3", "b/b#3" = ""),
          open = character())
eq(chain(f), "A/a#2", "closed or merged intermediate PR is not followed")
eq(f$calls(), "T/t#1", "closed or merged intermediate PR is not read")
eq(chain(fake(list("t/t#1" = ""))), character(), "no references")

## SpaDES.project#222 -> SpaDES.core#520 -> SpaDES.core#518: #520 is branched from #518,
## so only #520 is installed; #518's own references are still followed.
f <- fake(list("t/t#1" = "Depends-on: A/a#3", "a/a#3" = "Depends-on: A/a#2",
               "a/a#2" = "Depends-on: B/b#4", "b/b#4" = ""))
eq(chain(f), c("B/b#4", "A/a#3"), "upstream stacked on its own repo: one copy, deps kept")
