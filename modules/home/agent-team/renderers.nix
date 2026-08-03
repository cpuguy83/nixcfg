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

  codexReasoningEffort = {
    fast = "low";
    balanced = "medium";
    deep = "high";
  };

  modelFor = harness: role:
    let
      modelKey = if role.diverseModel or false then "adversarial" else role.modelClass;
    in
    team.models.${harness}.${modelKey};

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
  inherit codexReasoningEffort;

  supportedCapabilityProfiles = lib.attrNames copilotTools;

  copilotAgent = name: role:
    markdownAgent "${name}.agent.md"
      {
        inherit name;
        inherit (role) description;
        model = modelFor "copilot" role;
        tools = copilotTools.${role.capabilityProfile};
      }
      role.prompt;

  claudeAgent = name: role:
    markdownAgent "${name}.md"
      {
        inherit name;
        inherit (role) description;
        model = modelFor "claude" role;
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
      model_reasoning_effort = codexReasoningEffort.${role.modelClass};
      sandbox_mode = codexSandboxModes.${role.capabilityProfile};
    };

  claudeWrapperAgent = name: role:
    markdownAgent "${name}.md"
      {
        inherit name;
        inherit (role) description;
        model = team.models.claude.${role.modelClass};
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
    ]
  );
}
