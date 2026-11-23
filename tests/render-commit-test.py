"""render-module-rmd's commit step lands its render when the branch moved after the run started.

Run: python3 tests/render-commit-test.py [WORKFLOW]   (needs PyYAML and git; no network)

The `Commit results` step runs as written, in a shallow clone like the one actions/checkout
makes, against a local bare repository standing in for GitHub: url.<base>.insteadOf points
the step's tokenized https remote at it, and GIT_ALLOW_PROTOCOL=file refuses anything else.
WORKFLOW defaults to .github/workflows/render-module-rmd.yaml; give an older copy of the
file to see a case fail.
"""
import atexit
import os
import shutil
import subprocess
import sys
import tempfile

import yaml

WF = sys.argv[1] if len(sys.argv) > 1 else ".github/workflows/render-module-rmd.yaml"
BRANCH = "development"
REPO = "owner/repo"
M = "modA"


def check(cond, what):
    if not cond:
        raise SystemExit("FAIL: " + what)
    print("ok:", what)


with open(WF) as f:
    jobs = yaml.safe_load(f)["jobs"]
steps = jobs["commit"]["steps"]
download = next(s for s in steps
                if str(s.get("uses", "")).startswith("actions/download-artifact"))
step = next(s for s in steps if s.get("name") == "Commit results")
check(set(step["env"]) <= {"GH_TOKEN", "MODULE", "MODULE_DIR", "EXTRA_FILES"}
      and "${{" not in step["run"],
      "the step needs only the inputs this test supplies")
collect = next(s for s in jobs["render"]["steps"] if s.get("name") == "Collect rendered files")
check(set(collect["env"]) <= {"MODULE", "MODULE_DIR", "EXTRA_FILES"}
      and "${{" not in collect["run"],
      "the collect step needs only the inputs this test supplies")
upload = next(s for s in jobs["render"]["steps"]
              if str(s.get("uses", "")).startswith("actions/upload-artifact"))
check(upload["with"]["path"].strip() == "${{ runner.temp }}/rendered"
      and upload["with"]["if-no-files-found"] == "error",
      "the render uploads the collected folder, and fails without files")

T = tempfile.mkdtemp()
atexit.register(shutil.rmtree, T, True)
remote = os.path.join(T, "github", REPO + ".git")
seed = os.path.join(T, "seed")
with open(os.path.join(T, ".gitconfig"), "w") as f:
    f.write('[url "file://%s/github/"]\n' % T
            + "\tinsteadOf = https://x-access-token:token@github.com/\n")
ENV = {"PATH": os.environ["PATH"], "HOME": T, "GIT_CONFIG_NOSYSTEM": "1",
       "GIT_ALLOW_PROTOCOL": "file", "GIT_TERMINAL_PROMPT": "0"}


def git(cwd, *args):
    return subprocess.run(["git", "-c", "user.name=test", "-c", "user.email=test@example.com"]
                          + list(args), cwd=cwd, env=ENV, check=True, capture_output=True,
                          text=True).stdout


def push(files, message):
    """Commit `files` ({path: text}) on the branch tip in the seed clone and push them."""
    # The steps run in between push to the branch as well, so start from its current tip.
    if git(remote, "branch", "--list", BRANCH).strip():
        git(seed, "fetch", "-q", "file://" + remote, BRANCH)
        git(seed, "reset", "-q", "--hard", "FETCH_HEAD")
    for path, text in files.items():
        os.makedirs(os.path.dirname(os.path.join(seed, path)), exist_ok=True)
        with open(os.path.join(seed, path), "w") as f:
            f.write(text)
        git(seed, "add", path)
    git(seed, "commit", "-q", "-m", message)
    git(seed, "push", "-q", "file://" + remote, "HEAD:" + BRANCH)


def checkout(name):
    """The branch as it is now, shallow, as actions/checkout leaves it for a push run."""
    git(T, "clone", "-q", "--depth=1", "--branch", BRANCH, "file://" + remote, name)
    return os.path.join(T, name)


def render(module, version, date, text, d=""):
    """A module's rendered .md, keyed by its path in the repository."""
    v = (module, version, date, text)
    p = os.path.join(d, module)
    return {p + ".md": '---\ntitle: "%s"\nsubtitle: "v.%s"\ndate: "Last updated: %s"\n'
                       '---\n\n%s\n' % v}


def run_step(job, module, module_dir, files, extra=""):
    """Put `files` where download-artifact puts them, then run the step in checkout `job`."""
    temp = tempfile.mkdtemp(dir=T)
    path = (download["with"]["path"].replace("${{ runner.temp }}", temp)
            .replace("${{ inputs.module-dir || '.' }}", module_dir or "."))
    if "${{" in path:
        raise SystemExit("FAIL: cannot resolve the download path " + path)
    dest = os.path.join(job, path)
    os.makedirs(dest, exist_ok=True)
    # The artifact holds each file at its path relative to the module folder.
    for p, text in files.items():
        target = os.path.join(dest, os.path.relpath(p, module_dir or "."))
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "w") as f:
            f.write(text)
    with open(os.path.join(temp, "step.sh"), "w") as f:
        f.write(step["run"])
    env = dict(ENV, GH_TOKEN="token", MODULE=module, MODULE_DIR=module_dir,
               EXTRA_FILES=extra, GITHUB_REPOSITORY=REPO, GITHUB_REF_NAME=BRANCH,
               RUNNER_TEMP=temp)
    r = subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail",
                        os.path.join(temp, "step.sh")], cwd=job, env=env,
                       capture_output=True, text=True)
    if r.returncode:
        print(r.stdout + r.stderr)
    return r.returncode == 0


def on_branch(files):
    """Whether the tip of the branch holds exactly these files."""
    try:
        return all(git(remote, "show", "%s:%s" % (BRANCH, p)) == t for p, t in files.items())
    except subprocess.CalledProcessError:  # a file missing from the branch
        return False


os.makedirs(remote)
git(remote, "init", "-q", "--bare", "-b", BRANCH)
git(T, "init", "-q", "-b", BRANCH, seed)

# 1. A PR merge, then a version bump pushed while the merge's run was still rendering. The
#    runs queue, each checked out at its own push, and the merge's render lands first. Both
#    renders change the subtitle and date lines, so rebasing the bump's render onto the
#    merge's conflicted in both files on every attempt.
files = render(M, "1.0.0", "2026-10-09", "One parameter.")
files[M + ".R"] = "version 1.0.0\n"
push(files, "Add the module")
push({M + ".Rmd": "Two parameters.\n"}, "Merge pull request #1")
merge_run = checkout("merge-run")
push({M + ".R": "version 1.0.1\n"}, "Bump the version")
bump_run = checkout("bump-run")
older = render(M, "1.0.0", "2026-10-14", "Two parameters.")
newer = render(M, "1.0.1", "2026-10-14", "Two parameters.")
check(run_step(merge_run, M, "", older) and on_branch(older)
      and on_branch({M + ".R": "version 1.0.1\n"}),
      "the merge's run commits its render on top of the bump, keeping the bump")
check(run_step(bump_run, M, "", newer) and on_branch(newer),
      "the bump's run replaces the merge's render with its own")

# 2. Several modules in one repository, one commit job each from the same push: one lands
#    after the other checked out, and both renders stay.
files = render("modB", "1.0.0", "2026-10-09", "Text.", "modules/modB")
files.update(render("modC", "1.0.0", "2026-10-09", "Text.", "modules/modC"))
push(files, "Add two modules")
b_run, c_run = checkout("b-run"), checkout("c-run")
new_b = render("modB", "1.0.0", "2026-10-14", "Text.", "modules/modB")
new_c = render("modC", "1.0.0", "2026-10-14", "Text.", "modules/modC")
check(run_step(b_run, "modB", "modules/modB", new_b)
      and run_step(c_run, "modC", "modules/modC", new_c)
      and on_branch(new_b) and on_branch(new_c),
      "two modules' jobs from one push both land")

# 3. A push rejected once, as when two modules' commits reach GitHub together, is tried
#    again on a fresh fetch (after the step's 5 s pause).
hook = os.path.join(remote, "hooks", "pre-receive")
with open(hook, "w") as f:
    f.write("#!/bin/sh\n[ -e once ] && exit 0\ntouch once\n"
            "echo 'test: rejected once' >&2\nexit 1\n")
os.chmod(hook, 0o755)
latest = render(M, "1.0.1", "2026-10-15", "Two parameters.")
check(run_step(checkout("retry-run"), M, "", latest) and on_branch(latest),
      "a rejected push is tried again and lands")
os.remove(hook)

# 4. The branch already holds this render: nothing to commit, and the step succeeds.
tip = git(remote, "rev-parse", BRANCH)
check(run_step(checkout("same-run"), M, "", latest) and git(remote, "rev-parse", BRANCH) == tip,
      "an unchanged render makes no commit")

# 5. Only the .md is committed: an .html left beside it in the download stays off the branch.
md_only = render(M, "1.0.2", "2026-10-16", "Three parameters.")
check(run_step(checkout("md-run"), M, "", dict(md_only, **{M + ".html": "<p>Three.</p>\n"}))
      and on_branch(md_only)
      and not any(p.endswith(".html")
                  for p in git(remote, "ls-tree", "-r", "--name-only", BRANCH).split()),
      "the step commits the .md and no .html")

# 6. `extra-files`: a file the render writes besides the .md, such as the version badge a
#    module's README shows, is committed with it at its path in the module folder.
BADGE = "figures/moduleVersionBadge.png"
bumped = dict(render(M, "1.0.3", "2026-10-17", "Three parameters."), **{BADGE: "v1.0.3\n"})
check(run_step(checkout("extra-run"), M, "", bumped, BADGE) and on_branch(bumped),
      "an extra file is committed with the .md")
tip = git(remote, "rev-parse", BRANCH)
check(run_step(checkout("extra-same-run"), M, "", bumped, BADGE)
      and git(remote, "rev-parse", BRANCH) == tip,
      "an unchanged render and extra file make no commit")
in_dir = dict(render("modB", "1.0.1", "2026-10-17", "Text.", "modules/modB"),
              **{"modules/modB/" + BADGE: "v1.0.1\n"})
check(run_step(checkout("extra-dir-run"), "modB", "modules/modB", in_dir, BADGE)
      and on_branch(in_dir),
      "an extra file lands in the module's own folder")


# 7. The render job's collect step, which fills the folder the commit job downloads.
def run_collect(files, module, module_dir="", extra=""):
    """Run the collect step in a checkout holding `files` ({path: text}).

    Returns {path relative to the uploaded folder: text}, or None if the step failed.
    """
    job, temp = tempfile.mkdtemp(dir=T), tempfile.mkdtemp(dir=T)
    for p, text in files.items():
        os.makedirs(os.path.dirname(os.path.join(job, p)), exist_ok=True)
        with open(os.path.join(job, p), "w") as f:
            f.write(text)
    with open(os.path.join(temp, "collect.sh"), "w") as f:
        f.write(collect["run"])
    env = dict(ENV, MODULE=module, MODULE_DIR=module_dir, EXTRA_FILES=extra, RUNNER_TEMP=temp)
    r = subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail",
                        os.path.join(temp, "collect.sh")], cwd=job, env=env,
                       capture_output=True, text=True)
    if r.returncode:
        return None
    out = upload["with"]["path"].strip().replace("${{ runner.temp }}", temp)
    found = {}
    for root, _, names in os.walk(out):
        for n in names:
            with open(os.path.join(root, n)) as f:
                found[os.path.relpath(os.path.join(root, n), out)] = f.read()
    return found


rendered = {M + ".md": "md\n", M + ".html": "html\n", BADGE: "badge\n",
            "figures/issuesBadge.png": "issues\n"}
check(run_collect(rendered, M) == {M + ".md": "md\n"},
      "without extra-files only the .md is collected")
check(run_collect(rendered, M, extra=BADGE) == {M + ".md": "md\n", BADGE: "badge\n"},
      "a listed extra file is collected at its path, and nothing else")
nested = {"modules/modB/modB.md": "md\n", "modules/modB/" + BADGE: "badge\n"}
check(run_collect(nested, "modB", "modules/modB", BADGE) == {"modB.md": "md\n",
                                                             BADGE: "badge\n"},
      "paths are relative to the module folder")
check(run_collect({M + ".md": "md\n"}, M, extra=BADGE) is None,
      "a listed file the render did not write fails the step")
check(run_collect({M + ".html": "html\n"}, M) is None,
      "a render with no .md fails the step")
# Each of these names a file that exists, outside the module folder.
check(all(run_collect(dict(nested, **{"modules/outside.png": "x\n"}), "modB", "modules/modB", f)
          is None for f in ("../outside.png", "/etc/hostname", "figures/../../outside.png")),
      "a path outside the module folder fails the step")
