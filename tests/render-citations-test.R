## render-module-rmd's "Resolve citations in the .md" step, run as written on fixture modules.
## Without a top-level `bibliography`, or without a kept .md, the .md stays byte for byte as
## the render left it; with both, its citations, reference list, cross-references and text
## references are filled in. No module is knitted: each fixture holds the .Rmd's front matter
## and the .md `keep_md` would have left.
## Run: Rscript tests/render-citations-test.R [WORKFLOW]   (needs rmarkdown, bookdown, pandoc)
args <- commandArgs(TRUE)
wf <- if (length(args)) args[[1]] else ".github/workflows/render-module-rmd.yaml"

check <- function(cond, what) {
  if (!isTRUE(cond)) stop("FAIL: ", what, call. = FALSE)
  cat("ok:", what, "\n")
}

steps <- yaml::read_yaml(wf)$jobs$render$steps
nms <- vapply(steps, function(s) if (is.null(s$name)) "" else s$name, "")
step <- steps[[which(nms == "Resolve citations in the .md")]]
check(identical(step$shell, "Rscript {0}") && setequal(names(step$env), c("MODULE", "MODULE_DIR"))
      && !grepl("${{", step$run, fixed = TRUE),
      "the step needs only the inputs this test supplies")
check(which(nms == "Render module Rmd") < which(nms == step$name)
      && which(nms == step$name) < which(nms == "Collect rendered files"),
      "the step runs after the render and before the collect step")

code <- tempfile(fileext = ".R")
writeLines(step$run, code)

## Run the step in `root`, as the job does in the checkout; returns its output.
run_step <- function(root, m, module_dir = "") {
  old <- setwd(root)
  on.exit(setwd(old))
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), shQuote(code),
                                  stdout = TRUE, stderr = TRUE,
                                  env = c(paste0("MODULE=", m), paste0("MODULE_DIR=", module_dir))))
  status <- attr(out, "status")
  attr(out, "status") <- if (is.null(status)) 0L else status
  out
}

## A module folder holding <m>.Rmd (front matter only), the .md keep_md leaves (that front
## matter and the knitted body), and refs.bib.
fixture <- function(front, body = knitted, m = "modA", md = TRUE, dir = tempfile("module-")) {
  dir.create(dir, recursive = TRUE)
  yaml <- c("---", sprintf('title: "%s Manual"', m), front, "---", "")
  writeLines(yaml, file.path(dir, paste0(m, ".Rmd")))
  if (md) writeLines(c(yaml, body), file.path(dir, paste0(m, ".md")))
  writeLines(c("@misc{fixture,", "  author = {Fixture, Test},",
               "  title = {Fixture entry, not a real reference},", "  year = {2000}", "}"),
             file.path(dir, "refs.bib"))
  dir
}
bytes <- function(f) readBin(f, "raw", file.size(f))

keep <- c("output:", "  bookdown::html_document2:", "    keep_md: yes")
bib <- "bibliography: refs.bib"
## As knitr and kableExtra write them for html_document2: a text reference, a citation, an
## HTML table and figure block with bookdown labels, and an empty reference list.
knitted <- c(
  "(ref:modA) *modA*", "",
  "The range of variation [@fixture]. See Table \\@ref(tab:t1) and Figure \\@ref(fig:f1).",
  "Quoted 'as typed', from owner/repo@development.", "",
  '<table class="table">',
  "<caption>(\\#tab:t1)Parameters of (ref:modA).</caption>",
  "<tbody><tr><td> owner/repo@development </td><td> x &gt; 0 </td></tr></tbody>",
  "</table>", "",
  '<div class="figure">',
  '<img src="figures/f1.png" alt="(ref:modA) events, see Table \\@ref(tab:t1)." width="100%" />',
  '<p class="caption">(\\#fig:f1)(ref:modA) events, see Table \\@ref(tab:t1).</p>',
  "</div>", "",
  "## References {-}", "",
  '<div id="refs"></div>', "",
  "## Appendix", "", "After the references."
)

## 1. Front matter that does not opt in: the .md is not touched.
cases <- list(
  "no bibliography" = keep,
  "a bibliography that is not top-level" = c(keep, "editor_options:", "  bibliography: refs.bib"),
  "only a key that starts like `bibliography`" = c(keep, "bibliography-extra: refs.bib"),
  "a bibliography with a markdown output format" = c("output: github_document", bib),
  "a bibliography with keep_md off" =
    c("output:", "  bookdown::html_document2:", "    keep_md: no", bib)
)
for (what in names(cases)) {
  d <- fixture(cases[[what]])
  before <- bytes(file.path(d, "modA.md"))
  out <- run_step(d, "modA")
  check(attr(out, "status") == 0 && identical(bytes(file.path(d, "modA.md")), before)
        && setequal(list.files(d), c("modA.Rmd", "modA.md", "refs.bib"))
        && any(grepl("left as rendered", out)),
        paste0("the .md is left byte for byte with ", what))
}
d <- fixture(c(keep, bib), md = FALSE)
out <- run_step(d, "modA")
check(attr(out, "status") == 0 && !file.exists(file.path(d, "modA.md")),
      "a render that kept no .md is left to fail in the collect step")

## 2. A top-level bibliography and keep_md: the .md is converted.
d <- fixture(c(keep, bib, "link-citations: true"))
out <- run_step(d, "modA")
md <- readLines(file.path(d, "modA.md"), encoding = "UTF-8")
txt <- paste(md, collapse = "\n")
check(attr(out, "status") == 0 && !any(grepl("::warning::", out)), "the conversion succeeds")
check(!grepl("[@", txt, fixed = TRUE) && grepl('class="csl-entry"', txt)
      && grepl("[Fixture 2000](#ref-fixture)", txt, fixed = TRUE),
      "citations are resolved and the reference is listed")
check(which(grepl('class="csl-entry"', md))[1] < which(md == "## Appendix"),
      "the reference list is where the .Rmd put it")
check(!grepl("\\@ref(", txt, fixed = TRUE) && !grepl("(\\#", txt, fixed = TRUE)
      && grepl("Table 1: Parameters of <em>modA</em>.", txt, fixed = TRUE)
      && grepl("Figure 1: <em>modA</em> events", txt, fixed = TRUE)
      && grepl('See Table <a href="#tab:t1">1</a>', txt, fixed = TRUE),
      "figures and tables are numbered, and cross-references resolved")
check(!grepl("(ref:", txt, fixed = TRUE), "text references are resolved")
check(any(md == '<img src="figures/f1.png" alt="modA events, see Table 1." width="100%" />'),
      "the figure keeps its path and a valid <img> tag")
check(any(md == "<tbody><tr><td> owner/repo@development </td><td> x &gt; 0 </td></tr></tbody>"),
      "raw HTML is kept as written")
check(grepl("Quoted 'as typed', from owner/repo@development.", txt, fixed = TRUE),
      "quotes and owner/repo@ref stay as typed")
check(md[1] == "---" && md[2] == 'title: "modA Manual"' && any(md == bib),
      "the front matter is kept")
check(setequal(list.files(d), c("modA.Rmd", "modA.md", "refs.bib")),
      "no intermediate file is left beside the .md")

## 3. `module-dir`: a module in a folder of a repository with several.
root <- tempfile("repo-")
d <- fixture(c(keep, bib), m = "modB", body = sub("modA", "modB", knitted, fixed = TRUE),
             dir = file.path(root, "modules", "modB"))
out <- run_step(root, "modB", "modules/modB")
txt <- paste(readLines(file.path(d, "modB.md"), encoding = "UTF-8"), collapse = "\n")
check(attr(out, "status") == 0 && !grepl("[@", txt, fixed = TRUE)
      && grepl('class="csl-entry"', txt) && identical(list.files(root), "modules"),
      "a module in module-dir is converted in its own folder")

## 4. A conversion that fails leaves the .md as rendered, with a warning, and the job goes on.
d <- fixture(c(keep, "bibliography: missing.bib"))
before <- bytes(file.path(d, "modA.md"))
out <- run_step(d, "modA")
check(attr(out, "status") == 0 && identical(bytes(file.path(d, "modA.md")), before)
      && any(startsWith(out, "::warning::Could not resolve the citations in modA.md"))
      && !file.exists(file.path(d, "modA.knitted.md")),
      "a failed conversion leaves the .md as rendered and warns")
