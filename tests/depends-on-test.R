## Unit tests for install-depends-on/depends-on.R: the line parser and the skip rule.
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
