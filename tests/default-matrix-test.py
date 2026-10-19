"""With every depends-on-* input at its default, the reusable workflows behave as before.

Run: python3 tests/default-matrix-test.py   (needs PyYAML)
"""
import json
import re
import yaml

W = ".github/workflows/"
# R-CMD-check's matrix before the Depends-on options existed, in order.
TODAY = [
    ("macOS-latest", False, "release"), ("windows-latest", False, "devel"),
    ("windows-latest", False, "release"), ("windows-latest", False, "oldrel-1"),
    ("ubuntu-latest", False, "devel"), ("ubuntu-latest", False, "release"),
    ("ubuntu-latest", True, "release"), ("ubuntu-latest", False, "oldrel-1"),
]
BUMP = "depends-on-virtual-bump"
GATE = "depends-on-gate"


def load(name):
    with open(W + name + ".yaml") as f:
        return yaml.safe_load(f)


def check(cond, what):
    if not cond:
        raise SystemExit("FAIL: " + what)
    print("ok:", what)


# GitHub's status-check functions; a job `if:` naming none gets an implicit success().
STATUS = re.compile(r"\b(success|failure|always|cancelled)\(")


def needs(job):
    n = job.get("needs", [])
    return [n] if isinstance(n, str) else list(n)


def upstream(jobs, name):
    """Every job `name` needs, directly or through other jobs."""
    seen, todo = set(), needs(jobs[name])
    while todo:
        n = todo.pop()
        if n not in seen:
            seen.add(n)
            todo += needs(jobs[n])
    return seen


wf = load("R-CMD-check")
inputs = wf[True]["workflow_call"]["inputs"]  # PyYAML reads the key `on` as True
for n in (BUMP, GATE, "depends-on-reduced-matrix"):
    check(inputs[n]["default"] is False, "R-CMD-check input %s defaults to false" % n)

job = wf["jobs"]["R-CMD-check"]
cfg = job["strategy"]["matrix"]["config"]
literal = re.search(r"\|\| '(\[.*\])'", cfg).group(1)
legs = [(d["os"], d["nosuggests"], d["r"]) for d in json.loads(literal)]
check(legs == TODAY, "default matrix legs equal today's")
check(job["strategy"]["matrix"]["include"].endswith("inputs.extra-config) }}"),
      "extra-config is still appended when no reduced matrix is in use")

for name, main in [("R-CMD-check", "R-CMD-check"), ("test-coverage", "test-coverage"),
                   ("pkgdown", "pkgdown"), ("testthat-module", "testthat-module"),
                   ("render-module-rmd", "render"), ("pkgdown-module", "build")]:
    w = load(name)
    jobs = w["jobs"]
    inp = w[True]["workflow_call"]["inputs"]
    check(inp[BUMP]["default"] is False and inp[GATE]["default"] is False,
          name + ": virtual bump and gate default to false")
    check("inputs.depends-on-gate" in jobs["depends-on-gate"]["if"],
          name + ": the gate job is skipped unless opted in")
    check("'skipped'" in jobs[main]["if"], name + ": a skipped gate lets the main job run")
    for step in jobs[main]["steps"]:
        if isinstance(step.get("with"), dict) and step["with"].get("mode") == "prepare":
            check("inputs." + BUMP in step["if"], name + ": the prepare step needs the opt-in")
    post = [s for s in jobs[main]["steps"]
            if str(s.get("uses", "")).startswith("PredictiveEcology/actions/install-depends-on")
            and "with" not in s]
    check(len(post) == 1 and "if" not in post[0], name + ": the after-install step is unchanged")
    # The implicit success() is false when any upstream job was skipped, as the gate is by
    # default, so every job after the gate names a status function and checks its needs.
    for j in jobs:
        if j != GATE and GATE in upstream(jobs, j):
            cond = str(jobs[j].get("if", ""))
            check(STATUS.search(cond), name + ": " + j + " names a status function")
            for p in needs(jobs[j]):
                if p != GATE:
                    check("needs.%s.result == 'success'" % p in cond,
                          name + ": " + j + " runs only once " + p + " succeeded")
