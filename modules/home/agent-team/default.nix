{ config, lib, pkgs, pkgs-unstable, ... }:

let
  cfg = config.mine.agentTeam;

  team = import ./team.nix;
  roles = team.roles;
  roleNames = lib.attrNames roles;

  codexReview = import ./codex-review.nix {
    inherit lib pkgs;
    codexPackage = pkgs-unstable.codex;
    cfg = cfg.codex;
  };

  renderers = import ./renderers.nix {
    inherit lib pkgs team;
    inherit (codexReview) guard;
    wrapperPath = "${codexReview.review}/bin/codex-team-review";
  };

  roleFiles = lib.concatMapAttrs
    (name: role: {
      ".copilot/agents/${name}.agent.md".source = renderers.copilotAgent name role;
      ".claude/agents/${name}.md".source = renderers.claudeAgent name role;
      ".codex/agents/${name}.toml".source = renderers.codexAgent name role;
    })
    roles;

  # Claude-only: these depend on a second CLI, so they are not rendered for the
  # other two harnesses.
  claudeOnlyFiles = lib.concatMapAttrs
    (name: role: {
      ".claude/agents/${name}.md".source = renderers.claudeWrapperAgent name role;
    })
    team.claudeOnlyRoles;

  globalFiles = {
    ".copilot/copilot-instructions.md".source = renderers.globalInstructions;
    ".claude/CLAUDE.md".source = renderers.globalInstructions;
    ".codex/AGENTS.md".source = renderers.globalInstructions;
  };

  # Both activation scripts live in .sh files so they can be read as shell
  # rather than as escaped Nix strings. They are inlined verbatim into the
  # activation script, so `${...}` in them is bash, not Nix.
  substituteScript = replacements: file:
    lib.replaceStrings (lib.attrNames replacements) (lib.attrValues replacements)
      (builtins.readFile file);

  takeOverGlobalInstructions = substituteScript
    {
      "@storeDir@" = builtins.storeDir;
      "@targets@" = lib.concatStringsSep " " (
        map (p: ''"$HOME"/${lib.escapeShellArg p}'') (lib.attrNames globalFiles)
      );
    } ./takeover.sh;

  modelClasses = [
    "fast"
    "balanced"
    "deep"
  ];
  modelKeys = modelClasses ++ [ "adversarial" ];
  modelHarnesses = [
    "copilot"
    "claude"
    "codex"
  ];
  allHandoffs = lib.concatMap (role: role.handoffs) (lib.attrValues roles);

  claudeOnlyNames = lib.attrNames team.claudeOnlyRoles;

  # Claude Code writes ~/.claude/settings.json at runtime (/model, /effort,
  # /config all persist there), so it cannot become a read-only store symlink.
  # There is no drop-in directory for user-scope settings either: managed-settings
  # is system scope and outranks even CLI flags, which would take the override
  # away from the user. So merge the one key we own into the file in place,
  # atomically, and leave everything else exactly as the user left it.
  mergeClaudeFallbackModel = substituteScript
    {
      "@jq@" = "${pkgs.jq}/bin/jq";
      "@fallbackModel@" = builtins.toJSON cfg.claude.fallbackModel;
    } ./claude-settings.sh;
in
{
  options.mine.agentTeam = {
    codex = {
      enable = lib.mkEnableOption "Codex design and adversarial review agents for Claude" // {
        default = true;
      };

      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:1337/v1";
        description = ''
          API endpoint the review wrapper points Codex at. Codex has no
          standalone credentials on this host, so this defaults to the same
          local proxy `codex-proxied` uses. Reviews fail loudly if it is down.
        '';
      };

      timeoutSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 600;
        description = "Wall-clock limit for a single review before it is reported unavailable.";
      };

      maxBriefBytes = lib.mkOption {
        type = lib.types.ints.positive;
        default = 262144;
        description = "Largest design brief the wrapper will forward.";
      };

      maxBriefAgeSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3600;
        description = ''
          How long a brief slot stays usable after the wrapper issues it. This
          bounds how long an unused slot lingers, and lets the wrapper prune
          abandoned briefs from crashed sessions.
        '';
      };
    };

    claude.fallbackModel = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "sonnet" "haiku" ];
      description = ''
        Session-wide fallback chain merged into ~/.claude/settings.json. This is
        an outage safety net only; per-agent model choice stays in the agent
        definitions. Claude caps the chain at three entries and does not merge
        it across settings files.
      '';
    };

    standaloneBackupFileExtension = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "hm-backup";
      description = ''
        Backup extension to assume when nothing else supplied one. Taking over
        the global instruction paths means adopting files Home Manager does not
        yet own, which it only permits when it has somewhere to move the old
        content. The NixOS and nix-darwin modules cover that with
        `home-manager.backupFileExtension`; standalone Home Manager has no such
        option and reads the extension only from `home-manager switch -b EXT`,
        so an activation package invoked any other way would be refused. Set
        this on the standalone configuration to keep both entry points
        equivalent. An extension already present in the environment wins, and
        leaving this null simply means the takeover insists on being told.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = roleNames == team.expectedRoleNames;
        message = "agent-team: team.nix must define the canonical nine-role team";
      }
      {
        assertion = lib.all (name: builtins.match "team-[a-z0-9-]+" name != null) roleNames;
        message = "agent-team: role identifiers must use the team- namespace";
      }
      {
        assertion = lib.all
          (role: role.roleName != "" && role.description != "" && role.prompt != "")
          (lib.attrValues roles);
        message = "agent-team: every role requires a name, description, and prompt";
      }
      {
        assertion = lib.all
          (role: lib.elem role.modelClass modelClasses)
          (lib.attrValues roles);
        message = "agent-team: every role must use fast, balanced, or deep";
      }
      {
        assertion = lib.all
          (role: lib.elem role.capabilityProfile renderers.supportedCapabilityProfiles)
          (lib.attrValues roles);
        message = "agent-team: every role must use a supported capability profile";
      }
      {
        assertion = lib.all (handoff: builtins.hasAttr handoff roles) allHandoffs;
        message = "agent-team: role handoffs must target members of the canonical team";
      }
      {
        assertion = lib.all
          (name: !(lib.elem name roles.${name}.handoffs))
          roleNames;
        message = "agent-team: roles cannot hand work to themselves";
      }
      {
        assertion = lib.all
          (role: builtins.stringLength role.prompt < 30000)
          (lib.attrValues roles);
        message = "agent-team: role prompts must fit Copilot's 30,000-character limit";
      }
      {
        assertion = lib.all (name: lib.hasInfix name team.commonInstructions) roleNames;
        message = "agent-team: every role must be documented in the shared routing instructions";
      }
      {
        assertion = lib.all
          (harness: lib.all
            (model: builtins.hasAttr model team.models.${harness})
            modelKeys)
          modelHarnesses;
        message = "agent-team: every harness must map all semantic model classes";
      }

      # The Claude-only pair is not part of the canonical nine, so it needs the
      # same guarantees stated separately rather than inherited.
      {
        assertion = lib.all (name: builtins.match "team-[a-z0-9-]+" name != null) claudeOnlyNames;
        message = "agent-team: Claude-only agents must use the team- namespace";
      }
      {
        assertion = !(lib.any (name: builtins.hasAttr name roles) claudeOnlyNames);
        message = "agent-team: Claude-only agents must not shadow a canonical role";
      }
      {
        assertion = lib.all
          (role: role.roleName != "" && role.description != "" && role.prompt != "")
          (lib.attrValues team.claudeOnlyRoles);
        message = "agent-team: every Claude-only agent requires a name, description, and prompt";
      }
      {
        assertion = lib.all
          (role: builtins.hasAttr role.modelClass team.models.claude)
          (lib.attrValues team.claudeOnlyRoles);
        message = "agent-team: every Claude-only agent must map to a known Claude model class";
      }
      {
        # A prompt that still says @wrapper@ would send the agent to a command
        # the guard refuses, so the placeholder has to be present to be replaced.
        assertion = lib.all
          (role: lib.hasInfix "@wrapper@" role.prompt)
          (lib.attrValues team.claudeOnlyRoles);
        message = "agent-team: Claude-only agents must reference the wrapper via @wrapper@";
      }
      {
        assertion = lib.all (name: lib.hasInfix name team.commonInstructions) claudeOnlyNames;
        message = "agent-team: every Claude-only agent must be documented in the shared routing instructions";
      }
      {
        assertion = cfg.claude.fallbackModel == [ ]
          || builtins.length cfg.claude.fallbackModel <= 3;
        message = "agent-team: Claude accepts at most three fallback models";
      }
      {
        # The chain is embedded in a single-quoted shell literal, so a quote in a
        # model name would break out of it.
        assertion = !(lib.any (m: lib.hasInfix "'" m) cfg.claude.fallbackModel);
        message = "agent-team: fallback model names must not contain single quotes";
      }
      {
        # Each Claude-only agent picks its tool set and its guard mode from this
        # field, so an unknown mode would silently produce an unguarded agent.
        assertion = lib.all
          (role: lib.elem role.mode [ "design" "final" ])
          (lib.attrValues team.claudeOnlyRoles);
        message = "agent-team: Claude-only agents must declare mode = \"design\" or \"final\"";
      }
      {
        # The wrapper prunes abandoned briefs and codex homes older than
        # maxBriefAgeSeconds, but what actually bounds a live run is
        # timeoutSeconds. If the age limit were the shorter of the two, a second
        # review could delete the CODEX_HOME and output file of a first one that
        # is still running. Both directions fail closed, but a broken review is
        # worth an assertion rather than a debugging session.
        assertion = cfg.codex.maxBriefAgeSeconds >= cfg.codex.timeoutSeconds;
        message = "agent-team: maxBriefAgeSeconds must be at least timeoutSeconds, or the pruner can delete a running review's own files";
      }
      {
        # Interpolated into a `${VAR:-default}` inside a double-quoted bash
        # string, where a quote, brace or dollar would escape the literal.
        assertion = cfg.standaloneBackupFileExtension == null
          || builtins.match "[A-Za-z0-9._-]+" cfg.standaloneBackupFileExtension != null;
        message = "agent-team: standaloneBackupFileExtension must be a non-empty string of letters, digits, dots, dashes or underscores";
      }
    ];

    home.packages = lib.mkIf cfg.codex.enable [ codexReview.review ];

    home.file = roleFiles // globalFiles
      // (lib.optionalAttrs cfg.codex.enable claudeOnlyFiles);

    home.activation.agentTeamGlobalInstructions =
      lib.hm.dag.entryBefore [ "checkLinkTargets" ] takeOverGlobalInstructions;

    # Ordered before the takeover rather than merely before `checkLinkTargets`:
    # both would satisfy home-manager, but the takeover reads this variable to
    # decide whether adoption is allowed, and two entries sharing a single
    # `entryBefore` target are ordered by a tie-break this must not depend on.
    home.activation.agentTeamBackupFileExtension =
      lib.mkIf (cfg.standaloneBackupFileExtension != null)
        (lib.hm.dag.entryBefore [ "agentTeamGlobalInstructions" ] ''
          export HOME_MANAGER_BACKUP_EXT="''${HOME_MANAGER_BACKUP_EXT:-${cfg.standaloneBackupFileExtension}}"
        '');

    home.activation.agentTeamClaudeSettings =
      lib.hm.dag.entryAfter [ "writeBoundary" ] mergeClaudeFallbackModel;
  };
}
