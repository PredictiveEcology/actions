## Usage: Rscript unpin-remotes.R <DESCRIPTION path> <package>
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
f <- args[1]
pkg <- args[2]
stopifnot(file.exists(f), nzchar(pkg))

ln <- readLines(f)
before <- read.dcf(f)
start <- grep("^Remotes:", ln)
if (!length(start)) {
  cat("No Remotes: field -- nothing to unpin.\n")
  quit(status = 0)
}

## Field block: from "Remotes:" to just before the next field. DCF's own rule:
## a field starts on any non-empty line that does not begin with whitespace;
## continuation lines begin with a space or tab. (A name-pattern such as
## `^[A-Za-z][A-Za-z0-9@._-]*:` misses names containing "/", e.g.
## `Config/roxygen2/version:`, and swallows them into the Remotes value.)
isField <- nzchar(ln) & !grepl("^[[:space:]]", ln)
after <- which(isField & seq_along(ln) > start[1])
end <- if (length(after)) after[1] - 1L else length(ln)
body <- sub("^Remotes:", "", paste(ln[start[1]:end], collapse = " "))
refs <- trimws(unlist(strsplit(body, ",")))
refs <- refs[nzchar(refs)]
## Compare package names exactly rather than pattern-matching the ref: no
## escaping to get wrong, and "SpaDES.tools" cannot match "SpaDES.toolsExtra".
## Drops "@ref", then "owner/".
refPkg <- sub("^.*/", "", sub("@.*$", "", refs))
keep <- refs[refPkg != pkg]
cat("Remotes before:", paste(refs, collapse = ", "), "\n")
cat("Remotes after :",
    if (length(keep)) paste(keep, collapse = ", ") else "<field removed>", "\n")
repl <- if (length(keep))
  c("Remotes:", paste0("    ", keep,
                       c(rep(",", length(keep) - 1L), ""))) else character()
writeLines(c(ln[seq_len(start[1] - 1L)], repl,
             if (end < length(ln)) ln[(end + 1L):length(ln)]), f)

## Re-parse: a malformed rewrite must fail here, not at install. A rewrite can
## still be valid DCF and wrong (a neighbouring field folded into Remotes), so
## also require every other field to be unchanged.
result <- read.dcf(f)
stopifnot(nrow(result) == 1L)
others <- setdiff(colnames(before), "Remotes")
stopifnot(setequal(setdiff(colnames(result), "Remotes"), others))
changed <- others[vapply(others, function(x) !identical(before[1, x], result[1, x]),
                         logical(1))]
if (length(changed))
  stop("Unpinning Remotes changed other DESCRIPTION fields: ",
       paste(changed, collapse = ", "))
