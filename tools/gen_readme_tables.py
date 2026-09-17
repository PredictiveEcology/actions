#!/usr/bin/env python3
"""Regenerate the capability tables in PredictiveEcology/actions' README.

Reads every reusable workflow (those with an `on: workflow_call:` block) and
writes two tables between marker comments in README.md:

  <!-- BEGIN GENERATED: inputs --> ... <!-- END GENERATED: inputs -->
  <!-- BEGIN GENERATED: behaviour --> ... <!-- END GENERATED: behaviour -->

Usage:
  gen_readme_tables.py            # rewrite README.md in place
  gen_readme_tables.py --check    # exit 1 if README.md is out of date (CI)
"""
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
WF_DIR = ROOT / ".github" / "workflows"
README = ROOT / "README.md"

# Order the columns so related workflows sit together; anything new is appended.
ORDER = ["R-CMD-check", "test-coverage", "pkgdown", "test-downstream", "revdeps",
         "citation", "render-module-rmd", "testthat-module", "pkgdown-module"]

# Inputs worth a row, in reading order. Anything else a workflow declares is
# appended, so a new input shows up here the first time it is generated.
INPUT_ORDER = ["system-deps", "pandoc", "extra-env", "dependencies", "extra-packages",
               "post-install", "extra-repositories", "extra-apt", "cache-version",
               "error-on", "check-args", "build-args", "extra-config", "r-version",
               "module", "coverage", "url", "config", "cranonly", "quiet", "timeout",
               "downstream", "run-in-tmux"]


def load(path):
    doc = yaml.safe_load(path.read_text()) or {}
    # PyYAML parses a bare `on:` key as the boolean True.
    return doc, doc.get("on", doc.get(True)) or {}


def code(text):
    """The workflow minus whole-line comments, so prose can't be mistaken for config."""
    return "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))


def reusable():
    out = {}
    for path in sorted(WF_DIR.glob("*.y*ml")):
        doc, on = load(path)
        if isinstance(on, dict) and "workflow_call" in on:
            out[path.stem] = (doc, on["workflow_call"] or {}, path.read_text())
    return {k: out[k] for k in sorted(out, key=lambda k: (ORDER.index(k) if k in ORDER else 99, k))}


def cell(spec):
    """One input's cell: its default, or `required` when it has none."""
    if spec is None:
        return "yes"
    if "default" in spec:
        d = spec["default"]
        if isinstance(d, bool):
            return f"`{str(d).lower()}`"
        d = " ".join(str(d).split())
        if d == "":
            return "`\"\"`"
        return f"`{d}`" if len(d) <= 34 else f"`{d[:33]}`\u2026"
    return "**required**"


def inputs_table(wfs):
    names = []
    for _, call, _ in wfs.values():
        for n in (call.get("inputs") or {}):
            if n not in names:
                names.append(n)
    names.sort(key=lambda n: (INPUT_ORDER.index(n) if n in INPUT_ORDER else 99, n))
    head = "| Input | " + " | ".join(f"`{w}`" for w in wfs) + " |"
    rule = "|---" * (len(wfs) + 1) + "|"
    rows = [head, rule]
    for n in names:
        cells = []
        for _, call, _ in wfs.values():
            spec = (call.get("inputs") or {}).get(n, "absent")
            cells.append("&ndash;" if spec == "absent" else cell(spec))
        rows.append(f"| `{n}` | " + " | ".join(cells) + " |")
    return "\n".join(rows)


def r_versions(doc, call):
    """What R the workflow runs: fixed legs, a caller-supplied matrix, or one input."""
    fixed, from_input = [], []
    for job in (doc.get("jobs") or {}).values():
        matrix = (job.get("strategy") or {}).get("matrix") or {}
        for key in ("config", "include"):
            spec = matrix.get(key)
            if isinstance(spec, list):
                for leg in spec:
                    if isinstance(leg, dict) and "r" in leg:
                        fixed.append(f"{leg.get('os', '?').replace('-latest', '')}/{leg['r']}"
                                     + ("+nosuggests" if leg.get("nosuggests") else ""))
            elif isinstance(spec, str):
                m = re.search(r"fromJSON\(inputs\.([\w-]+)\)", spec)
                if m:
                    from_input.append(m.group(1))
    parts = []
    if fixed:
        parts.append(", ".join(sorted(set(fixed))))
    for name in dict.fromkeys(from_input):
        parts.append(f"+ caller's `{name}`" if fixed else f"caller's `{name}`")
    if not parts:
        parts.append(f"caller's `r-version`" if "r-version" in (call.get("inputs") or {}) else "release")
    return " ".join(parts)


def dep_source(doc, call, text):
    """Where R package dependencies are fetched from."""
    spec = (call.get("inputs") or {}).get("extra-repositories")
    if spec is not None:
        default = str(spec.get("default", ""))
        return "input, r-universe by default" if "r-universe" in default else "input, CRAN by default"
    if re.search(r"^\s*extra-repositories:\s*'?https://\S*r-universe", code(text), re.M):
        return "r-universe, fixed"
    if "install-Require@" in code(text):
        return "Require"
    return "CRAN only"


def behaviour_table(wfs):
    rows = [
        "| Behaviour | " + " | ".join(f"`{w}`" for w in wfs) + " |",
        "|---" * (len(wfs) + 1) + "|",
    ]

    def mark(fn):
        return "| " + " | ".join("yes" if fn(d, c, t) else "&ndash;" for d, c, t in wfs.values()) + " |"

    rows.append("| Uses `setup-r-deps` " + mark(lambda d, c, t: "setup-r-deps@" in code(t)))
    rows.append("| Honours `[skip-ci]` " + mark(
        lambda d, c, t: any("skip-ci" in str(j.get("if", "")) for j in (d.get("jobs") or {}).values())))
    rows.append("| Cancels superseded PR runs " + mark(lambda d, c, t: bool(d.get("concurrency"))))
    rows.append("| Dependency source | " + " | ".join(
        dep_source(d, c, t) for d, c, t in wfs.values()) + " |")
    rows.append("| Accepts secrets | " + " | ".join(
        ", ".join(f"`{s}`" for s in (c.get("secrets") or {})) or "&ndash;" for _, c, _ in wfs.values()) + " |")
    rows.append("| R versions tested | " + " | ".join(
        r_versions(d, c).replace("|", "\\|") for d, c, _ in wfs.values()) + " |")
    return "\n".join(rows)


def splice(text, name, table):
    begin, end = f"<!-- BEGIN GENERATED: {name} -->", f"<!-- END GENERATED: {name} -->"
    if begin not in text or end not in text:
        raise SystemExit(f"README.md is missing the {begin} / {end} markers")
    pre, rest = text.split(begin, 1)
    _, post = rest.split(end, 1)
    note = ("\n<!-- Generated by tools/gen_readme_tables.py from the workflow files. "
            "Do not edit by hand. -->\n\n")
    return f"{pre}{begin}{note}{table}\n\n{end}{post}"


def main():
    wfs = reusable()
    text = README.read_text()
    text = splice(text, "inputs", inputs_table(wfs))
    text = splice(text, "behaviour", behaviour_table(wfs))
    if "--check" in sys.argv:
        if text != README.read_text():
            print("README.md is out of date: run tools/gen_readme_tables.py and commit the result.")
            return 1
        print("README.md is up to date.")
        return 0
    README.write_text(text)
    print(f"README.md updated from {len(wfs)} reusable workflows.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
