{ lib, pkgs, team, guard, wrapperPath }:

let
  tomlFormat = pkgs.formats.toml { };

  copilotTools = {
    "orchestrator-readonly" = [ "read" "search" ];
    "analysis-readonly" = [ "read" "search" "web" ];
    "read-execute" = [ "read" "search" "execute" "web" ];
    "read-write-execute" = [ "read" "search" "edit" "execute" ];
    "review-readonly" = [ "read" "search" "execute" ];
    "adversarial-readonly" = [ "read" "search" "execute" "web" ];
    "git-pr-scoped" = [ "read" "search" "execute" "github/*" ];
    "bounded-watch" = [ "read" "search" "execute" "web" ];
  };

  claudeTools = {
    "orchestrator-readonly" = [ "Read" "Grep" "Glob" ];
    "analysis-readonly" = [ "Read" "Grep" "Glob" "WebFetch" "WebSearch" ];
    "read-execute" = [ "Read" "Grep" "Glob" "Bash" "WebFetch" "WebSearch" ];
    "read-write-execute" = [ "Read" "Grep" "Glob" "Bash" "Edit" "Write" "NotebookEdit" ];
    "review-readonly" = [ "Read" "Grep" "Glob" "Bash" ];
    "adversarial-readonly" = [ "Read" "Grep" "Glob" "Bash" "WebFetch" "WebSearch" ];
    "git-pr-scoped" = [ "Read" "Grep" "Glob" "Bash" ];
    "bounded-watch" = [ "Read" "Grep" "Glob" "Bash" "WebFetch" "WebSearch" ];
  };

  codexSandboxModes = {
    "orchestrator-readonly" = "read-only";
    "analysis-readonly" = "read-only";
    "read-execute" = "workspace-write";
    "read-write-execute" = "workspace-write";
    "review-readonly" = "read-only";
    "adversarial-readonly" = "read-only";
    "git-pr-scoped" = "workspace-write";
    "bounded-watch" = "read-only";
  };

  inherit (team) modelFor effortFor;

  yamlScalar = value: builtins.toJSON value;

  renderFrontmatter = attrs:
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: "${name}: ${yamlScalar value}") attrs
    );
  # Claude-only agents are constrained to fixed wrapper commands. The frontmatter
  # carries the PreToolUse hook that enforces it; `tools:` alone cannot express
  # "Bash, but only these commands". The matcher is `*` so every tool call is
  # gated and the guard decides, rather than listing tools twice and risking the
  # two lists drifting apart.
  #
  # The design reviewer additionally needs Write (to fill in the brief the wrapper
  # issued) and Read (Claude may require reading a file it is about to rewrite).
  # Both are confined by the same guard to the wrapper's private brief directory,
  # so neither widens what the agent can reach.
  claudeWrapperTools = {
    design = "Bash, Write, Read";
    final = "Bash";
  };


  markdownAgent = name: attrs: prompt:
    pkgs.writeText name ''
      ---
      ${renderFrontmatter attrs}
      ---

      ${prompt}
    '';
in
{
  supportedCapabilityProfiles = lib.attrNames copilotTools;

  # Session-local definitions intentionally override only canonical disk agents.
  # The two Claude-only wrapper agents retain their on-disk tool guards/hooks.
  claudeProxiedAgents = builtins.toJSON (lib.mapAttrs
    (_: role: {
      inherit (role) description;
      prompt = role.prompt;
      model = modelFor "claudeProxied" role;
      effort = effortFor "claudeProxied" role;
      tools = claudeTools.${role.capabilityProfile};
      background = false;
      permissionMode = "default";
    })
    team.roles);

  copilotAgent = name: role:
    markdownAgent "${name}.agent.md"
      {
        inherit name;
        inherit (role) description;
        model = modelFor "copilot" role;
        reasoningEffort = effortFor "copilot" role;
        tools = copilotTools.${role.capabilityProfile};
      }
      role.prompt;

  claudeAgent = name: role:
    markdownAgent "${name}.md"
      {
        inherit name;
        inherit (role) description;
        model = modelFor "claude" role;
        effort = effortFor "claude" role;
        tools = lib.concatStringsSep ", " claudeTools.${role.capabilityProfile};
        background = false;
        permissionMode = "default";
      }
      role.prompt;

  codexAgent = name: role:
    tomlFormat.generate "${name}.toml" {
      inherit name;
      inherit (role) description;
      developer_instructions = role.prompt;
      model = modelFor "codex" role;
      model_reasoning_effort = effortFor "codex" role;
      sandbox_mode = codexSandboxModes.${role.capabilityProfile};
    };

  claudeWrapperAgent = name: role:
    markdownAgent "${name}.md"
      {
        inherit name;
        inherit (role) description;
        model = modelFor "claude" role;
        effort = effortFor "claude" role;
        tools = claudeWrapperTools.${role.mode};
        background = false;
        permissionMode = "default";
        hooks = {
          PreToolUse = [
            {
              matcher = "*";
              hooks = [
                {
                  type = "command";
                  command = "${guard}/bin/codex-team-review-guard ${role.mode}";
                }
              ];
            }
          ];
        };
      }
      (lib.replaceStrings [ "@wrapper@" ] [ wrapperPath ] role.prompt);

  # The personal instructions migrated out of ~/.claude/CLAUDE.md stay verbatim and
  # come first: they are the user's own standing rules. The portable team routing
  # text is appended, so adopting the team does not silently drop those rules.
  globalInstructions = pkgs.writeText "global-agent-instructions.md" (
    lib.concatStringsSep "\n" [
      (lib.removeSuffix "\n" (builtins.readFile ./global-instructions.md))
      ""
      "---"
      ""
      team.commonInstructions
      ''
        ## Model and effort routing

        Copilot dispatch: when the task tool supports overrides, explicitly pass
        the following model and `reasoning_effort` for each role:
      ''
      (lib.concatStringsSep "\n" (lib.mapAttrsToList
        (name: role: "- `${name}`: model `${modelFor "copilot" role}`, reasoning_effort `${effortFor "copilot" role}`.")
        team.roles))
      ''
        Copilot agent frontmatter uses `reasoningEffort`. Older standalone
        clients (including 1.0.61) ignore that field; the guidance above only
        helps clients with task effort overrides and cannot enforce effort on
        clients without them. Main defaults use settings.json model/effortLevel.

        Native Claude keeps Claude models: Sonnet/medium for main and balanced
        roles, pinned claude-opus-5/high for deep/reviewer roles, Haiku/low for
        fast roles. Never substitute Fable. claude-proxied supplies the Copilot
        model/effort matrix via --agents for canonical names only, intentionally
        taking precedence over disk definitions without shadowing the two
        Claude-only guarded review agents.

        Native and proxied Codex use the OpenAI matrix, except their primary
        reviewer uses ${team.models.codex.reviewer}/${effortFor "codex" team.roles.team-reviewer}.
        Direct upstream cannot serve Opus, and Opus Responses support on the
        offline local proxy is unconfirmed. Both isolated Claude-to-Codex
        reviews are pinned to ${team.isolatedReview.model}/${team.isolatedReview.effort}.
        On proxied Claude these reviews need not provide model-family diversity.
        CLI defaults remain overridable by explicit user flags; no blanket
        Claude subagent model or effort environment override is installed.
      ''
    ]
  );
}
