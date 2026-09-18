"""Focused routing checks. Run with python3 modules/home/agent-team/test-routing.py.

Builds only team artifacts/wrappers, never activates. All CLI/settings probes use
a synthetic HOME. Fixtures (including discarded merge temps) are deliberately
retained; no personal configuration, credentials, or inference is used.
"""

import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import tempfile
import tomllib


ROOT = Path(__file__).resolve().parents[3]
# Retain tests in their own harness; never touch live claude/codex/etc scratch.
test_root = Path("/tmp/ai-agent-tmp/agent-team-tests")
for directory in (test_root.parent, test_root):
    directory.mkdir(mode=0o700, exist_ok=True)
    info = directory.lstat()
    assert stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid()
    assert stat.S_IMODE(info.st_mode) == 0o700, directory
fixture = Path(tempfile.mkdtemp(prefix="nixcfg-routing.", dir=test_root))
print(f"Retained synthetic fixtures: {fixture}", flush=True)
build_env = os.environ | {key: str(fixture) for key in ("TMPDIR", "TMP", "TEMP")}

PACKAGES = [
    "codex", "codex-proxied", "claude", "claude-proxied",
    "github-copilot-cli-wrapped", "codex-team-review",
    "github-copilot-desktop-wrapped", "opencode-wrapped",
]
PREFIX = f"""
let f = builtins.getFlake {json.dumps("path:" + str(ROOT))};
    c = f.nixosConfigurations.yavin4.config.home-manager.users.cpuguy83;
    names = builtins.fromJSON {json.dumps(json.dumps(PACKAGES))};
    packages = builtins.filter (p: builtins.elem (p.name or "") names) c.home.packages;
    files = builtins.mapAttrs (_: v: v.source)
        (f.inputs.nixpkgs.lib.filterAttrs
          (n: _: builtins.match "\\\\.(copilot|claude|codex)/.*" n != null)
          c.home.file);
in
"""


def command(args, **kwargs):
    kwargs.setdefault("env", build_env)
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, **kwargs).stdout


def evaluate(expression):
    return json.loads(command([
        "nix", "eval", "--impure", "--json", "--expr", PREFIX + expression,
    ]))


data = evaluate("""
{
  files = builtins.mapAttrs (_: toString) files;
  packages = builtins.listToAttrs (map (p: { name = p.name; value = toString p; }) packages);
  failures = map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
  copilotSettings = c.home.activation.agentTeamCopilotSettings.data;
  claudeSettings = c.home.activation.agentTeamClaudeSettings.data;
  takeover = c.home.activation.agentTeamGlobalInstructions.data;
  opencodeInstructions = toString c.xdg.configFile."opencode/AGENTS.md".source;
  opencodeTarget = c.xdg.configHome + "/opencode/AGENTS.md";
  desktopOriginal = toString f.nixosConfigurations.yavin4.pkgs.github-copilot;
}
""")
assert data["failures"] == [], data["failures"]
subprocess.run([
    "nix", "build", "--no-link", "--impure", "--expr",
    PREFIX + "packages ++ builtins.attrValues files",
], check=True, env=build_env)

ASTRA, LUNA, OPUS = "gpt-6-astra", "gpt-5.6-luna", "claude-opus-5"
expected = {
    "organizer": (ASTRA, "medium", "sonnet"),
    "implementer": (ASTRA, "medium", "sonnet"),
    "architect": (ASTRA, "xhigh", OPUS),
    "adversarial-reviewer": (ASTRA, "xhigh", OPUS),
    "debugger": (ASTRA, "high", OPUS),
    "reviewer": (OPUS, "high", OPUS),
    "pr-operator": (LUNA, "low", "haiku"),
    "verifier": (LUNA, "low", "haiku"),
    "watcher": (LUNA, "low", "haiku"),
}


def artifact(name):
    return Path(data["files"][name]).read_text()


def frontmatter(text):
    return {
        key: json.loads(value)
        for key, value in (
            line.split(": ", 1) for line in text.split("---", 2)[1].strip().splitlines()
        )
    }


for role, (model, effort, native) in expected.items():
    copilot = frontmatter(artifact(f".copilot/agents/team-{role}.agent.md"))
    claude = frontmatter(artifact(f".claude/agents/team-{role}.md"))
    codex = tomllib.loads(artifact(f".codex/agents/team-{role}.toml"))
    assert (copilot["model"], copilot["reasoningEffort"]) == (model, effort)
    assert "reasoning_effort" not in copilot
    assert (claude["model"], claude["effort"]) == (native, "high" if effort == "xhigh" else effort)
    assert (codex["model"], codex["model_reasoning_effort"]) == (
        (ASTRA, "xhigh") if role == "reviewer" else (model, effort)
    )
    instructions = artifact(".copilot/copilot-instructions.md")
    assert f"`team-{role}`: model `{model}`, reasoning_effort `{effort}`" in instructions

for mode in ("design", "final"):
    agent = frontmatter(artifact(f".claude/agents/team-codex-{mode}-reviewer.md"))
    assert (agent["model"], agent["effort"]) == ("sonnet", "medium")
    hook = agent["hooks"]["PreToolUse"][0]
    assert hook["matcher"] == "*"
    assert hook["hooks"][0]["command"].endswith(f"/bin/codex-team-review-guard {mode}")
    assert agent["tools"] == ("Bash, Write, Read" if mode == "design" else "Bash")
print("PASS: 27 canonical artifacts, two guarded agents, dispatch guidance, HM assertions")

env = {
    "HOME": str(fixture), "PATH": "/run/current-system/sw/bin", "LC_ALL": "C",
    "TMPDIR": "/incoming/tmpdir", "TMP": "/incoming/tmp", "TEMP": "/incoming/temp",
}

BINARIES = {
    "github-copilot-cli-wrapped": "copilot",
    "github-copilot-desktop-wrapped": "github",
    "opencode-wrapped": "opencode",
}


def wrapper(name):
    return (Path(data["packages"][name]) / "bin" / BINARIES.get(name, name)).read_text()


setup_path = re.search(r"source (\S+) codex", wrapper("codex")).group(1)
setup = Path(setup_path).read_text()
assert "base=/tmp/ai-agent-tmp\n" in setup
temp_base = fixture / "agent-temp"
test_setup = fixture / "temp-env.sh"
test_setup.write_text(setup.replace("base=/tmp/ai-agent-tmp\n", f"base={temp_base}\n"))


def isolated(script):
    # The built policy has the literal production root. Substitute only that
    # root in a fixture copy, so error tests cannot damage real agent scratch.
    assert setup_path in script
    return script.replace(setup_path, str(test_setup))


def capture(name, args):
    # Replace only the exact raw exec target in memory, not any on-disk wrapper.
    script, count = re.subn(r"exec /nix/store/[^ \n]+/bin/(?:claude|codex)\b", "capture", wrapper(name))
    assert count == 1, name
    harness = name.split("-")[0]
    prelude = f"""
capture() {{
  [[ $TMPDIR == {temp_base}/{harness} && $TMP == "$TMPDIR" && $TEMP == "$TMPDIR" ]]
  [[ $PWD == {fixture} && $(umask) == 0027 ]]
  {"[[ $CLAUDE_CODE_TMPDIR == $TMPDIR ]]" if harness == "claude" else ":"}
  printf '%s\\0' "$@"
}}
umask 027
"""
    output = command([
        "bash", "-c", prelude + isolated(script), name, *args,
    ], env=env, cwd=fixture)
    return output.decode().rstrip("\0").split("\0")


for name in ("claude", "claude-proxied"):
    args = capture(name, ["-p", "test prompt"])
    assert args[:4] == ["--model", "sonnet" if name == "claude" else ASTRA, "--effort", "medium"]
    if name == "claude-proxied":
        agents = json.loads(args[args.index("--agents") + 1])
        assert set(agents) == {"team-" + role for role in expected}
        for role, (model, effort, _) in expected.items():
            agent = agents["team-" + role]
            assert (agent["model"], agent["effort"]) == (model, effort)
            native = frontmatter(artifact(f".claude/agents/team-{role}.md"))
            assert agent["tools"] == native["tools"].split(", ")
            assert agent["permissionMode"] == native["permissionMode"]
            assert agent["background"] is False
            assert agent["prompt"] in artifact(f".claude/agents/team-{role}.md")
    for explicit in (
        ["--model", "user-model", "--effort", "low", "--agents", "{}", "-p", "prompt"],
        ["--model=user-model", "--effort=low", "--agents={}", "-p", "prompt"],
    ):
        assert capture(name, explicit) == explicit
    for utility in (["--version"], ["--help"], ["mcp", "list"], ["plugin", "list"],
                    ["--verbose", "doctor"], ["--settings", "{}", "auth", "status"]):
        assert capture(name, utility) == utility
    # An option value that resembles a command is not itself a command.
    assert capture(name, ["--system-prompt", "doctor", "-p", "prompt"])[:2] == args[:2]
    for selection in (["--agent", "team-architect"], ["--agent=team-reviewer"]):
        selected = capture(name, selection)
        assert "--model" not in selected and "--effort" not in selected
        assert ("--agents" in selected) == (name == "claude-proxied")

for name in ("codex", "codex-proxied"):
    for user in ([], ["--version"], ["--help"], ["app-server"], ["app-server", "--help"],
                 ["exec", "prompt"], ["review"], ["resume", "--last"],
                 ["-c", 'model="user-model"', "-c", 'model_reasoning_effort="low"'],
                 ["--model", "user-model", "prompt"]):
        args = capture(name, user)
        assert args[:4] == ["-c", f'model="{ASTRA}"', "-c", 'model_reasoning_effort="medium"']
        defaults = args[:len(args) - len(user)] if user else args
        assert defaults[::2] == ["-c"] * (len(defaults) // 2)
        assert args[len(defaults):] == user
        assert ('model_provider="proxy"' in defaults) == (name == "codex-proxied")
    for profile in (
        ["-p", "chosen"], ["--profile", "chosen"], ["--profile=chosen"],
        ["-pchosen"], ["-p=chosen"], ["exec", "--profile", "chosen", "prompt"],
    ):
        args = capture(name, profile)
        defaults = args[:-len(profile)]
        assert args[len(defaults):] == profile
        assert not any(arg.startswith(("model=", "model_reasoning_effort=")) for arg in defaults)
        assert ('model_provider="proxy"' in defaults) == (name == "codex-proxied")
    assert capture(name, ["exec", "--", "--profile"])[:4] == [
        "-c", f'model="{ASTRA}"', "-c", 'model_reasoning_effort="medium"',
    ]

proxy = wrapper("claude-proxied")
shim = re.search(r"(/nix/store/[^:\"\n]+-codex-proxied-shim)/bin", proxy).group(1)
assert (Path(shim) / "bin/codex").resolve() == (
    Path(data["packages"]["codex-proxied"]) / "bin/codex-proxied"
).resolve()
review = wrapper("codex-team-review")
assert f"""-c 'model="{ASTRA}"'""" in review
assert """-c 'model_reasoning_effort="xhigh"'""" in review
assert review.count('timeout "$TIMEOUT"') == 1  # shared by design and final
assert "--sandbox read-only" in review and "--ignore-user-config" in review
print("PASS: wrapper argv defaults/overrides/utilities, proxy JSON/shim, isolated review pin")

# Do not invoke utilities that inspect credentials. Help/version alone exit
# without inference. app-server --help checks the plugin entry path, not a server.
for name in ("claude", "claude-proxied", "codex", "codex-proxied"):
    for args in (["--version"], ["--help"]):
        assert command(["bash", "-c", isolated(wrapper(name)), name, *args], env=env, cwd=fixture)
    if name.startswith("codex"):
        assert b"app-server" in command([
            "bash", "-c", isolated(wrapper(name)), name, "app-server", "--help",
        ], env=env, cwd=fixture)
print("PASS: real wrapper help/version and Codex app-server help (synthetic HOME)")

# makeWrapper launchers retain argv/library/PATH setup and use the same policy.
for name, binary in BINARIES.items():
    script = isolated(wrapper(name))
    script, count = re.subn(
        r'^exec -a "\$0" "/nix/store/[^"\n]+"  "\$@"[ \t]*$',
        'capture "$@"', script, flags=re.MULTILINE,
    )
    assert count == 1, name
    expected_root = temp_base / ("opencode" if binary == "opencode" else "copilot")
    output = command([
        "bash", "-c",
        'capture() { printf "%s\\0" "$TMPDIR" "$TMP" "$TEMP" "$@"; }\n' + script,
        binary, "--version", "argument with spaces",
    ], env=env, cwd=fixture).decode().rstrip("\0").split("\0")
    assert output == [str(expected_root)] * 3 + ["--version", "argument with spaces"]

desktop_package = Path(data["packages"]["github-copilot-desktop-wrapped"])
original_package = Path(data["desktopOriginal"])
desktop_name = "share/applications/GitHub Copilot.desktop"
desktop = (desktop_package / desktop_name).read_text()
original = (original_package / desktop_name).read_text()
assert desktop == original.replace(
    f"Exec={original_package}/bin/github", f"Exec={desktop_package}/bin/github",
)
assert f"Exec={desktop_package}/bin/github" in desktop
assert f"Exec={original_package}/bin/github" not in desktop
assert (desktop_package / "bin/git-credential-copilot").resolve() == (
    original_package / "bin/git-credential-copilot"
).resolve()
assert (desktop_package / "lib").is_dir()

for harness in ("claude", "codex", "copilot", "opencode"):
    directory = temp_base / harness
    info = directory.stat()
    assert stat.S_IMODE(info.st_mode) == 0o700 and info.st_uid == os.getuid()
assert stat.S_IMODE(temp_base.stat().st_mode) == 0o700

# No cleanup: a later launch leaves unrelated scratch and directory inode alone.
sentinel = temp_base / "codex/keep"
sentinel.write_text("retained")
before = (temp_base / "codex").stat().st_ino
capture("codex", ["--version"])
assert sentinel.read_text() == "retained"
assert (temp_base / "codex").stat().st_ino == before

# Parent state is unaffected; sourcing also restores positional arguments.
command([
    "bash", "-c", f"""
umask 027
set -- parent arguments
bash -c {shlex.quote(isolated(wrapper("codex")).replace('exec ', 'true ', 1))} child --version
[[ $TMPDIR == /incoming/tmpdir && $TMP == /incoming/tmp && $TEMP == /incoming/temp ]]
[[ $(umask) == 0027 && $PWD == {fixture} && $* == 'parent arguments' ]]
source {test_setup} codex
[[ $* == 'parent arguments' && $(umask) == 0027 && $PWD == {fixture} ]]
""",
], env=env, cwd=fixture)

# Invalid base AND harness topologies fail before a target can be reached.
for level in ("base", "harness"):
    for kind in ("symlink", "file", "public", "special-mode", "missing-parent"):
        case = fixture / f"invalid-{level}-{kind}"
        case.mkdir()
        base = case / "base"
        bad = base if level == "base" else base / "codex"
        if level == "harness":
            base.mkdir(mode=0o700)
        if kind == "symlink":
            bad.symlink_to(temp_base / "codex", target_is_directory=True)
        elif kind == "file":
            bad.write_text("not a directory")
        elif kind in ("public", "special-mode"):
            bad.mkdir(mode=0o700)
            bad.chmod(0o755 if kind == "public" else 0o1700)
        else:
            # A missing ancestor must not be created via mkdir -p.
            base = case / "absent/base"
        invalid_setup = setup.replace("base=/tmp/ai-agent-tmp\n", f"base={base}\n")
        result = subprocess.run([
            "bash", "-c", invalid_setup + "\nprintf REACHED", "test", "codex",
        ], env=env, cwd=fixture, capture_output=True)
        assert result.returncode != 0 and b"agent-temp:" in result.stderr
        assert b"REACHED" not in result.stdout

# The system root is foreign-owned for a normal user; validation must reject it
# before trying to create a harness. No privileged chown or foreign file reads.
if os.getuid() != 0:
    foreign = setup.replace("base=/tmp/ai-agent-tmp\n", "base=/\n")
    result = subprocess.run([
        "bash", "-c", foreign + "\nprintf REACHED", "test", "codex",
    ], env=env, cwd=fixture, capture_output=True)
    assert result.returncode != 0 and b"owned" in result.stderr and not result.stdout
print("PASS: all launch environments, private/idempotent dirs, failure paths, parent state, desktop")

generic = (ROOT / "modules/home/agent-team/global-instructions.md").read_text()
assert Path(data["opencodeInstructions"]).read_text() == generic
assert "team-organizer" not in generic and "@wrapper@" not in generic
assert 'mktemp -d "$TMPDIR/<project>-<purpose>.XXXXXX"' in generic
assert "Optimize code for human readability" in generic
for name in (".copilot/copilot-instructions.md", ".claude/CLAUDE.md", ".codex/AGENTS.md"):
    assert artifact(name) == instructions and artifact(name).startswith(generic)
assert shlex.quote(data["opencodeTarget"]) in data["takeover"]

HARNESS = """
set -euo pipefail
VERBOSE_ARG=""
warnEcho() { printf '%s\\n' "$*" >&2; }
verboseEcho() { :; }
errorEcho() { printf '%s\\n' "$*" >&2; }
# Retain discarded temps instead of deleting fixture files.
rm() { :; }
run() {
  if [[ -v DRY_RUN ]]; then return 0; fi
  "$@"
  if [[ $1 == chmod && ${TEST_RACE:-} == yes ]]; then
    touch "$HOME/.copilot/settings.json"
  fi
}
"""


def merge(home, kind="copilot", dry=False, race=False):
    test_env = env | {"HOME": str(home)}
    if dry:
        test_env["DRY_RUN"] = "1"
    if race:
        test_env["TEST_RACE"] = "yes"
    return subprocess.run([
        "bash", "-c", HARNESS + data[kind + "Settings"],
    ], env=test_env, cwd=fixture, check=True, capture_output=True)


owned = {"model": ASTRA, "effortLevel": "medium"}
home = fixture / "merge"
settings = home / ".copilot/settings.json"
settings.parent.mkdir(parents=True)
original = {
    "model": "old", "effortLevel": "low", "permissions": {"allow": ["read"]}, "other": 42,
    "env": {"USER_SETTING": "preserve", "TMPDIR": "/user/setting"},
}
settings.write_text(json.dumps(original))
settings.chmod(0o640)
merge(home)
assert json.loads(settings.read_text()) == original | owned
assert settings.stat().st_mode & 0o777 == 0o640
before = settings.stat()
merge(home)
assert (before.st_ino, before.st_mtime_ns) == (settings.stat().st_ino, settings.stat().st_mtime_ns)
for invalid in ("{", "[]", "null", "1", "", "{}\n{}"):
    settings.write_text(invalid)
    assert b"not a JSON object" in merge(home).stderr
    assert settings.read_text() == invalid

settings.write_text(json.dumps(original))
before = settings.read_bytes()
merge(home, dry=True)
assert settings.read_bytes() == before
assert b"changed while merging" in merge(home, race=True).stderr
assert settings.read_bytes() == before

missing = fixture / "missing"
merge(missing)
created = missing / ".copilot/settings.json"
assert json.loads(created.read_text()) == owned
assert created.stat().st_mode & 0o777 == 0o600
dry_home = fixture / "dry"
merge(dry_home, dry=True)
assert not dry_home.exists()
for parent_link in (False, True):
    linked = fixture / ("linked-dir" if parent_link else "linked-file")
    linked.mkdir()
    if parent_link:
        (linked / ".copilot").symlink_to(settings.parent)
    else:
        (linked / ".copilot").mkdir()
        (linked / ".copilot/settings.json").symlink_to(settings)
    assert b"symlink" in merge(linked).stderr
    assert settings.read_bytes() == before
nonregular = fixture / "nonregular"
(nonregular / ".copilot/settings.json").mkdir(parents=True)
assert b"not a regular file" in merge(nonregular).stderr

claude_settings = home / ".claude/settings.json"
claude_settings.parent.mkdir()
claude_settings.write_text(json.dumps({
    "model": "user-model", "effortLevel": "low", "permissions": {},
    "env": {"USER_SETTING": "preserve", "CLAUDE_CODE_TMPDIR": "/user/setting"},
}))
merge(home, "claude")
assert json.loads(claude_settings.read_text()) == {
    "model": "user-model", "effortLevel": "low", "permissions": {},
    "env": {"USER_SETTING": "preserve", "CLAUDE_CODE_TMPDIR": "/user/setting"},
    "fallbackModel": ["sonnet", "haiku"],
}
print("PASS: owned-key merges, permissions, no-op, malformed/non-object, dry-run, race, symlinks")

# OpenCode participates in the same fail-before-mutation adoption as the other
# global targets. Redirect its configured absolute XDG target to synthetic HOME.
adopt_home = fixture / "adoption"
adopt_target = adopt_home / ".config/opencode/AGENTS.md"
adopt_target.parent.mkdir(parents=True)
old_rules = adopt_home / "old-rules.md"
old_rules.write_text("retain existing OpenCode rules")
adopt_target.symlink_to(old_rules)
takeover = data["takeover"].replace(data["opencodeTarget"], str(adopt_target))
result = subprocess.run([
    "bash", "-c", HARNESS + takeover,
], env=env | {"HOME": str(adopt_home)}, cwd=fixture, capture_output=True)
assert result.returncode != 0 and b"no backup mechanism" in result.stderr
assert adopt_target.is_symlink()
command([
    "bash", "-c", HARNESS + takeover,
], env=env | {"HOME": str(adopt_home), "HOME_MANAGER_BACKUP_EXT": "backup"}, cwd=fixture)
assert not adopt_target.is_symlink() and adopt_target.read_text() == old_rules.read_text()
print("PASS: shared generic instructions, generic-only OpenCode rules and safe adoption")

# The reviewer bypasses ordinary CLI wrappers. Capture its raw executable route
# while retaining its capability, sandbox, isolation and runtime cleanup logic.
stub = fixture / "review-capture"
stub.write_text(f"#!{sys.executable}\n" + """
import json
import os
from pathlib import Path
import sys
args = sys.argv[1:]
result = {
    "args": args,
    "env": {k: os.environ.get(k) for k in ("TMPDIR", "TMP", "TEMP", "CODEX_HOME")},
    "home_mode": Path(os.environ["CODEX_HOME"]).stat().st_mode & 0o777,
    "prompt": sys.stdin.read(),
}
Path(args[args.index("--output-last-message") + 1]).write_text(json.dumps(result))
""")
stub.chmod(0o700)
review_script, count = re.subn(
    r'(timeout "\$TIMEOUT" )/nix/store/\S+/bin/codex\b',
    rf"\g<1>{stub}", isolated(review),
)
assert count == 1
review_binary = fixture / "codex-team-review"
review_binary.write_text(review_script)
review_binary.chmod(0o700)


def review_call(*args, check=True):
    return subprocess.run(
        [str(review_binary), *map(str, args)], env=env, cwd=fixture,
        capture_output=True, check=check,
    )


brief_dir = Path(review_call("brief-dir").stdout.decode().strip())
assert brief_dir == temp_base / "codex/codex-team-review"
assert stat.S_IMODE(brief_dir.stat().st_mode) == 0o700
brief = Path(review_call("new-brief").stdout.decode().strip())
assert re.fullmatch(r"[0-9a-f]{32}\.brief", brief.name) and not brief.exists()
issued = brief.with_suffix(".issued")
assert stat.S_IMODE(issued.stat().st_mode) == 0o600
brief.write_text("Synthetic design brief.")
brief.chmod(0o600)

guard_path = frontmatter(artifact(".claude/agents/team-codex-design-reviewer.md"))[
    "hooks"
]["PreToolUse"][0]["hooks"][0]["command"].split()[0]
guard_script = Path(guard_path).read_text().replace(
    str(Path(data["packages"]["codex-team-review"]) / "bin/codex-team-review"),
    str(review_binary),
)
for tool, field, value, allowed in (
    ("Write", "file_path", str(brief), True),
    ("Read", "file_path", str(issued), False),
    ("Write", "file_path", str(brief_dir / "bad.brief"), False),
    ("Bash", "command", f"{review_binary} design {brief}", True),
    ("Bash", "command", f"{review_binary} design {brief}; pwd", False),
):
    result = subprocess.run(
        ["bash", "-c", guard_script, "guard", "design"], env=env, cwd=fixture,
        input=json.dumps({"tool_name": tool, "tool_input": {field: value}}).encode(),
        capture_output=True,
    )
    assert result.returncode == (0 if allowed else 2), result.stderr

captured = json.loads(review_call("design", brief).stdout)
assert "Synthetic design brief." in captured["prompt"]
assert not brief.exists() and not issued.exists()
assert review_call("design", brief, check=False).returncode == 64
forged = brief_dir / ("a" * 32 + ".brief")
assert review_call("design", forged, check=False).returncode == 64
for kind in ("symlink", "hardlink", "writable"):
    unsafe = Path(review_call("new-brief").stdout.decode().strip())
    if kind == "symlink":
        unsafe.symlink_to(sentinel)
    elif kind == "hardlink":
        unsafe.hardlink_to(sentinel)
    else:
        unsafe.write_text("Synthetic unsafe brief.")
        unsafe.chmod(0o666)
    assert review_call("design", unsafe, check=False).returncode == 64
assert sentinel.read_text() == "retained"

repo = fixture / "review-repo"
(repo / ".git").mkdir(parents=True)
final_capture = json.loads(review_call("final", repo).stdout)
for captured in (captured, final_capture):
    child_env = captured["env"]
    assert [child_env[k] for k in ("TMPDIR", "TMP", "TEMP")] == [str(temp_base / "codex")] * 3
    codex_home = Path(child_env["CODEX_HOME"])
    assert codex_home.parent == fixture / ".cache/codex-team-review-home"
    assert not codex_home.is_relative_to(temp_base) and captured["home_mode"] == 0o700
    assert not codex_home.exists()  # existing narrowly scoped runtime cleanup
    args = captured["args"]
    assert 'shell_environment_policy.inherit="core"' in args
    assert not any(arg.startswith("shell_environment_policy.set") for arg in args)
    assert args[args.index("--sandbox") + 1] == "read-only"
    assert "--ignore-user-config" in args and "project_doc_max_bytes=0" in args
    assert "mcp_servers={}" in args
assert sentinel.read_text() == "retained"
print("PASS: review raw environment, guard/capabilities, replay rejection, separate CODEX_HOME, cleanup")
