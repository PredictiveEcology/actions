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
check(set(step["env"]) <= {"GH_TOKEN", "BOT_SLUG", "MODULE", "MODULE_DIR", "EXTRA_FILES"}
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


def run_step(job, module, module_dir, files, extra="", bot_slug=""):
    """Put `files` where download-artifact puts them, then run the step in checkout `job`.

    `bot_slug` stands for the docs-bot token step's `app-slug` output; empty, as when no
    DOCS_BOT_KEY was passed. A stub `gh` answers the step's lookup of the bot's user id.
    """
    temp = tempfile.mkdtemp(dir=T)
    bin_dir = os.path.join(temp, "bin")
    os.makedirs(bin_dir)
    with open(os.path.join(bin_dir, "gh"), "w") as f:
        f.write('#!/bin/sh\n[ "$1" = api ] && [ "$2" = "/users/${BOT_SLUG}[bot]" ] '
                '&& [ "$3" = --jq ] && [ "$4" = .id ] && echo 12345 && exit 0\n'
                'echo "unexpected: gh $*" >&2; exit 1\n')
    os.chmod(os.path.join(bin_dir, "gh"), 0o755)
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
               RUNNER_TEMP=temp, BOT_SLUG=bot_slug,
               PATH=bin_dir + os.pathsep + ENV["PATH"])
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


def tracked(path):
    """Whether the tip of the branch holds `path`."""
    return path in git(remote, "ls-tree", "-r", "--name-only", BRANCH).split()


# 8. Event-flow figures. SpaDES.core's module template writes figures/<module>_eventFlow.png
#    and one figures/<module>_io_<event>.png per event; the README shows them, so they are
#    collected without being listed, and no other figure is.
FLOW, IO = "figures/%s_eventFlow.png", "figures/%s_io_%s.png"
figs = {FLOW % M: "flow\n", IO % (M, "init"): "init\n", IO % (M, "plot"): "plot\n"}
check(run_collect(dict(rendered, **figs), M) == dict({M + ".md": "md\n"}, **figs),
      "the module's event-flow figures are collected without being listed")
check(run_collect(dict(rendered, **figs), M, extra=BADGE)
      == dict({M + ".md": "md\n", BADGE: "badge\n"}, **figs),
      "event-flow figures and listed extra files are collected together")
check(run_collect({M + ".md": "md\n", IO % (M + "Mod", "x"): "other\n"}, M) == {M + ".md": "md\n"},
      "a render with no event-flow figures collects only the .md, not another module's figure")
check(run_collect({"modules/modB/modB.md": "md\n", "modules/modB/" + FLOW % "modB": "flow\n"},
                  "modB", "modules/modB") == {"modB.md": "md\n", FLOW % "modB": "flow\n"},
      "event-flow figures are collected relative to the module folder")

# 9. The figures are committed with the .md, and a figure for an event the module no longer
#    has is removed.
fig_run = dict(render(M, "1.0.4", "2026-10-18", "Events."), **figs)
check(run_step(checkout("fig-run"), M, "", fig_run) and on_branch(fig_run),
      "the event-flow figures are committed with the .md")
figs2 = {FLOW % M: "flow 2\n", IO % (M, "init"): "init\n", IO % (M, "burn"): "burn\n"}
fig_run2 = dict(render(M, "1.0.5", "2026-10-19", "Events."), **figs2)
check(run_step(checkout("fig-run2"), M, "", fig_run2) and on_branch(fig_run2)
      and not tracked(IO % (M, "plot")),
      "a figure for an event that no longer exists is removed")

# 10. A render that wrote no event-flow figures (the module could not be read, or its .Rmd
#     has no such chunks) removes the committed ones, as its .md no longer shows them; the
#     badge and other figures stay.
others = {"figures/other.png": "other\n", IO % (M + "Mod", "x"): "x\n"}
push(others, "Add other figures")
no_figs = render(M, "1.0.6", "2026-10-20", "No events.")
check(run_step(checkout("nofig-run"), M, "", no_figs) and on_branch(no_figs)
      and on_branch(others) and tracked(BADGE)
      and not any(tracked(p) for p in figs2),
      "a render without figures removes the module's figures and keeps the rest")

# 11. Several modules in one repository: one module's figures land in its own folder, and
#     another module's stay as they are.
c_flow = {"modules/modC/" + FLOW % "modC": "c flow\n"}
push(c_flow, "Add modC's figure")
b_figs = dict(render("modB", "1.0.2", "2026-10-20", "Text.", "modules/modB"),
              **{"modules/modB/" + FLOW % "modB": "b flow\n",
                 "modules/modB/" + IO % ("modB", "init"): "b init\n"})
check(run_step(checkout("fig-dir-run"), "modB", "modules/modB", b_figs)
      and on_branch(b_figs) and on_branch(c_flow),
      "a module's figures land in its own folder and leave another module's alone")

# 11b. A figure also listed in `extra-files` is committed with the rest, not refused.
listed = dict(render(M, "1.0.6", "2026-10-21", "Listed."), **{FLOW % M: "flow listed\n"})
check(run_step(checkout("listed-run"), M, "", listed, FLOW % M) and on_branch(listed),
      "a figure also listed in extra-files is committed")

# 11c. The removal of old figures matches files in figures/ itself, not in a folder below it
#      whose name happens to start like an event figure's.
deep = {"figures/%s_io_sub/deep.png" % M: "deep\n"}
push(deep, "Add a figure in a subfolder")
check(run_step(checkout("deep-run"), M, "",
               dict(render(M, "1.0.6", "2026-10-21", "Deep."), **{FLOW % M: "flow deep\n"}))
      and on_branch(deep),
      "a file in a folder below figures/ is not removed")

# 12. A repository whose .gitignore covers figures/ still gets them: its README shows them.
push({".gitignore": "figures/\n"}, "Ignore figures")
ignored = dict(render(M, "1.0.7", "2026-10-21", "Events."), **{FLOW % M: "flow 3\n"})
check(run_step(checkout("ignored-run"), M, "", ignored) and on_branch(ignored),
      "the figures are committed even where .gitignore covers them")

# 13. The render installs the font the figures are drawn in, and the packages that draw them.
sysdeps = next(s for s in jobs["render"]["steps"]
               if str(s.get("uses", "")).startswith("PredictiveEcology/actions/install-module-sysdeps"))
check("fonts-noto-core" in sysdeps.get("with", {}).get("extra-apt", "").split(),
      "the render installs fonts-noto-core")
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "install-Rmd-pkgs",
                       "action.yaml")) as f:
    rmd_pkgs = f.read()
check(all('"%s"' % p in rmd_pkgs
          for p in ("ggplot2", "ragg", "systemfonts", "textshaping", "xml2", "xmlparsedata")),
      "install-Rmd-pkgs installs the packages that draw the figures")

# 14. The render job's checkout holds the figures the last render committed. They are removed
#     before the render, so a render that writes none (the module cannot be read, has no
#     events, its chunks are skipped or removed) collects none, and the commit removes them.
render_steps = jobs["render"]["steps"]
clean = next((s for s in render_steps if s.get("name") == "Remove the previous event-flow figures"),
             None)
names = [s.get("name") for s in render_steps]
check(clean is not None and set(clean.get("env", {})) <= {"MODULE", "MODULE_DIR"}
      and "${{" not in clean["run"]
      and names.index(clean["name"]) < names.index("Render module Rmd"),
      "the render job removes the previous event-flow figures before rendering")


def run_clean(files, module, module_dir=""):
    """Run the clean step in a checkout holding `files`; return the files left."""
    job, temp = tempfile.mkdtemp(dir=T), tempfile.mkdtemp(dir=T)
    for p, text in files.items():
        os.makedirs(os.path.dirname(os.path.join(job, p)), exist_ok=True)
        with open(os.path.join(job, p), "w") as f:
            f.write(text)
    with open(os.path.join(temp, "clean.sh"), "w") as f:
        f.write(clean["run"])
    env = dict(ENV, MODULE=module, MODULE_DIR=module_dir)
    subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail",
                    os.path.join(temp, "clean.sh")], cwd=job, env=env, check=True)
    left = {}
    for root, _, ns in os.walk(job):
        for n in ns:
            left[os.path.relpath(os.path.join(root, n), job)] = True
    return set(left)


keep = {M + ".Rmd": "rmd\n", BADGE: "badge\n", "figures/other.png": "other\n",
        IO % (M + "Mod", "x"): "x\n"}
check(run_clean(dict(keep, **figs), M) == set(keep),
      "the clean step removes the module's event-flow figures and nothing else")
check(run_clean({"modules/modB/" + FLOW % "modB": "b\n", "modules/modC/" + FLOW % "modC": "c\n"},
                "modB", "modules/modB") == {"modules/modC/" + FLOW % "modC"},
      "the clean step removes only its own module's figures")
check(run_clean(keep, M) == set(keep), "the clean step succeeds when there are no figures")


def tip_author():
    return git(remote, "log", "-1", "--format=%an <%ae>", BRANCH).strip()


# 15. Docs bot. Without DOCS_BOT_KEY the commit is github-actions[bot]'s, as before; with it,
#     the app's bot account's, so GitHub attributes the commit to the app.
check(tip_author() == "github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>",
      "without the docs-bot key the render is committed as github-actions[bot]")
check(run_step(checkout("bot-run"), M, "", render(M, "1.0.8", "2026-10-22", "Bot."),
               bot_slug="pe-docs-bot")
      and tip_author() == "pe-docs-bot[bot] <12345+pe-docs-bot[bot]@users.noreply.github.com>",
      "with the docs-bot key the render is committed as the app's bot account")

# 16. The token step runs only when a key was passed, and the push falls back to GITHUB_TOKEN.
#     The render job skips the bot's own push: a render of the bot's commit always differs from
#     it, so a caller with no `paths:` filter would otherwise commit again on every bot commit.
bot = next((s for s in steps if str(s.get("uses", "")).startswith("actions/create-github-app-token")),
           None)
check(bot is not None and bot.get("id") == "docs-bot"
      and bot.get("if", "").replace(" ", "") == "${{env.HAS_DOCS_BOT_KEY=='true'}}"
      and jobs["commit"]["env"]["HAS_DOCS_BOT_KEY"].replace(" ", "")
      == "${{secrets.DOCS_BOT_KEY!=''}}"
      and bot["with"]["private-key"].replace(" ", "") == "${{secrets.DOCS_BOT_KEY}}",
      "the token step runs only when DOCS_BOT_KEY was passed")
check(len(bot["uses"].split("@", 1)[1]) == 40
      and all(c in "0123456789abcdef" for c in bot["uses"].split("@", 1)[1]),
      "the action handed the key is pinned to a commit SHA, not a movable tag")
check(step["env"]["GH_TOKEN"].replace(" ", "")
      == "${{steps.docs-bot.outputs.token||secrets.GITHUB_TOKEN}}"
      and step["env"]["BOT_SLUG"].replace(" ", "") == "${{steps.docs-bot.outputs.app-slug}}",
      "the push uses the app's token when there is one, else GITHUB_TOKEN")
with open(WF) as f:
    wf = yaml.safe_load(f)
check(wf[True]["workflow_call"]["secrets"]["DOCS_BOT_KEY"]["required"] is False,
      "DOCS_BOT_KEY is optional")
check("github.event_name == 'push' && github.actor ==" in jobs["render"]["if"]
      and "[bot]')" in jobs["render"]["if"],
      "the render job skips the docs bot's own push")
check("DOCS_BOT_KEY" not in yaml.safe_dump(jobs["render"]),
      "the render job, which runs the module's code, never sees the key")
