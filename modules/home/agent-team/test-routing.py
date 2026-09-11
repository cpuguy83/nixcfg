"""Focused routing checks. Run with python3 modules/home/agent-team/test-routing.py.

Builds only team artifacts/wrappers, never activates. All CLI/settings probes use
a synthetic HOME. Fixtures (including discarded merge temps) are deliberately
retained; no personal configuration, credentials, or inference is used.
"""

import json
from pathlib import Path
import re
import subprocess
import tempfile
import tomllib


ROOT = Path(__file__).resolve().parents[3]
PACKAGES = [
    "codex", "codex-proxied", "claude", "claude-proxied",
    "github-copilot-cli-wrapped", "codex-team-review",
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
}
""")
assert data["failures"] == [], data["failures"]
subprocess.run([
    "nix", "build", "--no-link", "--impure", "--expr",
    PREFIX + "packages ++ builtins.attrValues files",
], check=True)

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

fixture = Path(tempfile.mkdtemp(prefix="agent-routing-tests."))
print(f"Retained synthetic fixtures: {fixture}", flush=True)
env = {"HOME": str(fixture), "PATH": "/run/current-system/sw/bin", "LC_ALL": "C"}


def wrapper(name):
    return (Path(data["packages"][name]) / "bin" / name).read_text()


def capture(name, args):
    # Replace only the exact raw exec target in memory, not any on-disk wrapper.
    script, count = re.subn(r"exec /nix/store/[^ \n]+/bin/(?:claude|codex)\b", "capture", wrapper(name))
    assert count == 1, name
    output = command([
        "bash", "-c", "capture() { printf '%s\\0' \"$@\"; }\n" + script, name, *args,
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
    binary = str(Path(data["packages"][name]) / "bin" / name)
    for args in (["--version"], ["--help"]):
        assert command([binary, *args], env=env, cwd=fixture)
    if name.startswith("codex"):
        assert b"app-server" in command([binary, "app-server", "--help"], env=env, cwd=fixture)
print("PASS: real wrapper help/version and Codex app-server help (synthetic HOME)")

HARNESS = """
set -euo pipefail
VERBOSE_ARG=""
warnEcho() { printf '%s\\n' "$*" >&2; }
verboseEcho() { :; }
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
original = {"model": "old", "effortLevel": "low", "permissions": {"allow": ["read"]}, "other": 42}
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
claude_settings.write_text('{"model":"user-model","effortLevel":"low","permissions":{}}')
merge(home, "claude")
assert json.loads(claude_settings.read_text()) == {
    "model": "user-model", "effortLevel": "low", "permissions": {},
    "fallbackModel": ["sonnet", "haiku"],
}
print("PASS: owned-key merges, permissions, no-op, malformed/non-object, dry-run, race, symlinks")
