## render-module-rmd's "Resolve citations in the .md" step, run as written on fixture modules.
## Without a top-level `bibliography`, or without a kept .md, the .md stays byte for byte as
## the render left it; with both, its citations, reference list, cross-references and text
## references are filled in. Most fixtures hold the .Rmd's front matter and the .md `keep_md`
## would have left; the last is a small real .Rmd, rendered by the workflow's own render step.
## Run: Rscript tests/render-citations-test.R [WORKFLOW]   (needs rmarkdown, bookdown, pandoc)
args <- commandArgs(TRUE)
wf <- if (length(args)) args[[1]] else ".github/workflows/render-module-rmd.yaml"

last <- character() # the output of the last step run, shown when a check fails
check <- function(cond, what) {
  if (!isTRUE(cond)) {
    cat("---- output of the last step run:\n", last, sep = "\n")
    stop("FAIL: ", what, call. = FALSE)
  }
  cat("ok:", what, "\n")
}

steps <- yaml::read_yaml(wf)$jobs$render$steps
nms <- vapply(steps, function(s) if (is.null(s$name)) "" else s$name, "")
step <- steps[[which(nms == "Resolve citations in the .md")]]
render_step <- steps[[which(nms == "Render module Rmd")]]
check(identical(step$shell, "Rscript {0}") && setequal(names(step$env), c("MODULE", "MODULE_DIR"))
      && !grepl("${{", step$run, fixed = TRUE),
      "the step needs only the inputs this test supplies")
check(which(nms == "Render module Rmd") < which(nms == step$name)
      && which(nms == step$name) < which(nms == "Collect rendered files"),
      "the step runs after the render and before the collect step")

## Run `code` (a step's `run:` text) in `root`, as the job does in the checkout; returns its
## output, with its exit status as attribute "status".
run_step <- function(root, m, module_dir = "", code = step$run) {
  f <- tempfile(fileext = ".R")
  writeLines(code, f)
  old <- setwd(root)
  on.exit(setwd(old))
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), shQuote(f),
                                  stdout = TRUE, stderr = TRUE,
                                  env = c(paste0("MODULE=", m), paste0("MODULE_DIR=", module_dir))))
  status <- attr(out, "status")
  attr(out, "status") <- if (is.null(status)) 0L else status
  last <<- out
  out
}

## A module folder holding <m>.Rmd (front matter only), the .md keep_md leaves (that front
## matter and the knitted body), and refs.bib. `front = NULL`: no front matter at all.
fixture <- function(front, body = knitted, m = "modA", md = TRUE, eol = "\n",
                    dir = tempfile("module-")) {
  dir.create(dir, recursive = TRUE)
  yaml <- if (is.null(front)) character() else
    c("---", sprintf('title: "%s Manual"', m), front, "---", "")
  writeLines(yaml, file.path(dir, paste0(m, ".Rmd")), sep = eol)
  if (md) writeLines(c(yaml, body), file.path(dir, paste0(m, ".md")), sep = eol)
  writeLines(c("@misc{fixture,", "  author = {Fixture, Test},",
               "  title = {Fixture entry, not a real reference},", "  year = {2000}", "}"),
             file.path(dir, "refs.bib"))
  dir
}
bytes <- function(f) readBin(f, "raw", file.size(f))
read <- function(f) readLines(f, encoding = "UTF-8", warn = FALSE)

keep <- c("output:", "  bookdown::html_document2:", "    keep_md: yes")
bib <- "bibliography: refs.bib"
## As knitr and kableExtra write them for html_document2: a text reference, a citation, an
## HTML table and two figure blocks with bookdown labels (the second inside a link, as
## `fig.link` writes it, with a cross-reference to no label), and an empty reference list.
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
  '<div class="figure">',
  paste0('<a href="https://example.org/f2"><img src="figures/f2.png" ',
         'alt="Unresolved \\@ref(tab:none)." width="50%" /></a>'),
  '<p class="caption">(\\#fig:f2)Unresolved \\@ref(tab:none).</p>',
  "</div>", "",
  "## References {-}", "",
  '<div id="refs"></div>', "",
  "## Appendix", "", "After the references."
)

## 1. Front matter that does not opt in: the .md is not touched.
cases <- list(
  "no front matter" = list(front = NULL),
  "no bibliography" = list(front = keep),
  "no bibliography, CRLF line endings" = list(front = keep, eol = "\r\n"),
  "a bibliography that is not top-level" =
    list(front = c(keep, "editor_options:", "  bibliography: refs.bib")),
  "only a key that starts like `bibliography`" =
    list(front = c(keep, "bibliography-extra: refs.bib")),
  "a bibliography with a markdown output format" = list(front = c("output: github_document", bib)),
  "a bibliography with keep_md off" =
    list(front = c("output:", "  bookdown::html_document2:", "    keep_md: no", bib)),
  "a bibliography with the output format as a string" =
    list(front = c("output: bookdown::html_document2", bib))
)
for (what in names(cases)) {
  d <- do.call(fixture, cases[[what]])
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
md <- read(file.path(d, "modA.md"))
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
check(any(md == paste0('<a href="https://example.org/f2"><img src="figures/f2.png" ',
                       'alt="Unresolved ??." width="50%" /></a>')),
      "an <img> inside a link, with an unresolved cross-reference, keeps a valid tag")
check(any(md == "<tbody><tr><td> owner/repo@development </td><td> x &gt; 0 </td></tr></tbody>"),
      "raw HTML is kept as written")
check(grepl("Quoted 'as typed', from owner/repo@development.", txt, fixed = TRUE),
      "quotes and owner/repo@ref stay as typed")
check(md[1] == "---" && md[2] == 'title: "modA Manual"' && any(md == bib),
      "the front matter is kept")
check(setequal(list.files(d), c("modA.Rmd", "modA.md", "refs.bib")),
      "no intermediate file is left beside the .md")

## 3. The same with CRLF line endings.
d <- fixture(c(keep, bib, "link-citations: true"), eol = "\r\n")
out <- run_step(d, "modA")
txt <- paste(read(file.path(d, "modA.md")), collapse = "\n")
check(attr(out, "status") == 0 && !any(grepl("::warning::", out))
      && !grepl("[@", txt, fixed = TRUE) && grepl('class="csl-entry"', txt)
      && grepl("Figure 1: <em>modA</em> events", txt, fixed = TRUE)
      && grepl('<img src="figures/f1.png" alt="modA events, see Table 1." width="100%" />', txt,
               fixed = TRUE),
      "a .md with CRLF line endings is converted")

## 4. `module-dir`: a module in a folder of a repository with several.
root <- tempfile("repo-")
d <- fixture(c(keep, bib), m = "modB", body = sub("modA", "modB", knitted, fixed = TRUE),
             dir = file.path(root, "modules", "modB"))
out <- run_step(root, "modB", "modules/modB")
txt <- paste(read(file.path(d, "modB.md")), collapse = "\n")
check(attr(out, "status") == 0 && !grepl("[@", txt, fixed = TRUE)
      && grepl('class="csl-entry"', txt) && identical(list.files(root), "modules"),
      "a module in module-dir is converted in its own folder")

## 5. A conversion that fails leaves the .md as rendered, with a warning, and the job goes on.
d <- fixture(c(keep, "bibliography: missing.bib"))
before <- bytes(file.path(d, "modA.md"))
out <- run_step(d, "modA")
check(attr(out, "status") == 0 && identical(bytes(file.path(d, "modA.md")), before)
      && any(startsWith(out, "::warning::Could not resolve the citations in modA.md"))
      && setequal(list.files(d), c("modA.Rmd", "modA.md", "refs.bib")),
      "a failed conversion leaves the .md as rendered and warns")

## 6. So does one that would break a figure: here the <img> edit is switched off, so
##    bookdown's links break the tags and pandoc writes them as text, without an error.
broken <- sub("regmatches(x, g) <- lapply(", "g <- lapply(", step$run, fixed = TRUE)
check(!identical(broken, step$run), "the test can switch the <img> edit off")
d <- fixture(c(keep, bib))
before <- bytes(file.path(d, "modA.md"))
out <- run_step(d, "modA", code = broken)
check(attr(out, "status") == 0 && identical(bytes(file.path(d, "modA.md")), before)
      && any(startsWith(out, "::warning::Could not resolve the citations in modA.md")),
      "a conversion that would show an <img> tag as text leaves the .md as rendered")

## 7. A small real .Rmd, rendered by the workflow's own render step and then converted: a
##    knitr::kable() HTML table and a base-graphics figure whose caption has a text
##    reference and a cross-reference, as knitr writes them.
d <- tempfile("module-")
dir.create(d)
writeLines(c(
  "---", 'title: "modR Manual"', keep, bib, "link-citations: true", "---", "",
  "(ref:modR) *modR*", "",
  "The range of variation [@fixture]. Figure \\@ref(fig:f1) plots Table \\@ref(tab:t1).", "",
  "```{r t1, echo = FALSE}",
  'knitr::kable(data.frame(x = 1:2, y = c("a", "b")), format = "html",',
  '             caption = "Values of (ref:modR).")',
  "```", "",
  '```{r f1, echo = FALSE, fig.cap = "(ref:modR) values, from Table \\\\@ref(tab:t1)."}',
  "plot(1:2)",
  "```", "",
  "## References {-}", "", '<div id="refs"></div>'
), file.path(d, "modR.Rmd"))
writeLines(c("@misc{fixture,", "  author = {Fixture, Test},",
             "  title = {Fixture entry, not a real reference},", "  year = {2000}", "}"),
           file.path(d, "refs.bib"))
out <- run_step(d, "modR", code = render_step$run)
check(attr(out, "status") == 0 && file.exists(file.path(d, "modR.md")),
      "the render step renders the real .Rmd and keeps its .md")
kept_md <- read(file.path(d, "modR.md"))
out <- run_step(d, "modR")
md <- read(file.path(d, "modR.md"))
txt <- paste(md, collapse = "\n")
src <- function(x) regmatches(x, regexpr('<img src="[^"]+"', x))
check(attr(out, "status") == 0 && !any(grepl("::warning::", out))
      && !grepl("[@", txt, fixed = TRUE) && grepl('class="csl-entry"', txt)
      && !grepl("\\@ref(", txt, fixed = TRUE) && !grepl("(ref:", txt, fixed = TRUE)
      && grepl("Table 1: Values of <em>modR</em>.", txt, fixed = TRUE)
      && grepl("Figure 1: <em>modR</em> values, from Table", txt, fixed = TRUE),
      "the real .Rmd's .md is converted: citations, numbers and text references")
check(length(src(kept_md)) == 1 && identical(src(md), src(kept_md))
      && any(grepl('^<img src="[^"]+" alt="modR values, from Table 1\\."', md)),
      "the real .Rmd's figure keeps its path and a valid <img> tag")
