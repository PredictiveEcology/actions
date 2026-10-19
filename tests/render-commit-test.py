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
    steps = yaml.safe_load(f)["jobs"]["commit"]["steps"]
download = next(s for s in steps
                if str(s.get("uses", "")).startswith("actions/download-artifact"))
step = next(s for s in steps if s.get("name") == "Commit results")
check(set(step["env"]) <= {"GH_TOKEN", "MODULE", "MODULE_DIR"} and "${{" not in step["run"],
      "the step needs only the inputs this test supplies")

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
    """A module's rendered .md and .html, keyed by their paths in the repository."""
    v = (module, version, date, text)
    p = os.path.join(d, module)
    return {p + ".md": '---\ntitle: "%s"\nsubtitle: "v.%s"\ndate: "Last updated: %s"\n'
                       '---\n\n%s\n' % v,
            p + ".html": '<h1 class="title">%s</h1>\n<h3 class="subtitle">v.%s</h3>\n'
                         '<h4 class="date">Last updated: %s</h4>\n<p>%s</p>\n' % v}


def run_step(job, module, module_dir, files):
    """Put `files` where download-artifact puts them, then run the step in checkout `job`."""
    temp = tempfile.mkdtemp(dir=T)
    path = (download["with"]["path"].replace("${{ runner.temp }}", temp)
            .replace("${{ inputs.module-dir || '.' }}", module_dir or "."))
    if "${{" in path:
        raise SystemExit("FAIL: cannot resolve the download path " + path)
    dest = os.path.join(job, path)
    os.makedirs(dest, exist_ok=True)
    for p, text in files.items():
        with open(os.path.join(dest, os.path.basename(p)), "w") as f:
            f.write(text)
    with open(os.path.join(temp, "step.sh"), "w") as f:
        f.write(step["run"])
    env = dict(ENV, GH_TOKEN="token", MODULE=module, MODULE_DIR=module_dir,
               GITHUB_REPOSITORY=REPO, GITHUB_REF_NAME=BRANCH, RUNNER_TEMP=temp)
    r = subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail",
                        os.path.join(temp, "step.sh")], cwd=job, env=env,
                       capture_output=True, text=True)
    if r.returncode:
        print(r.stdout + r.stderr)
    return r.returncode == 0


def on_branch(files):
    """Whether the tip of the branch holds exactly these files."""
    return all(git(remote, "show", "%s:%s" % (BRANCH, p)) == t for p, t in files.items())


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
