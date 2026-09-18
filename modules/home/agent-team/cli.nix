{ lib, pkgs, pkgs-unstable, team, renderers }:

let
  tempEnv = import ./temp-env.nix { inherit pkgs; };

  # Config overrides are global Codex options, valid for utility commands and
  # app-server too. Do not use interactive-only --model/--profile flags here.
  # Explicit profiles supply their own defaults. Later user -c overrides (and
  # explicit --model on sessions) also take precedence.
  codexWrapper = name: proxied: pkgs.writeShellApplication {
    inherit name;
    text = ''
      # shellcheck source=/dev/null
      source ${tempEnv} codex

      defaults=(
        -c ${lib.escapeShellArg "model=${builtins.toJSON team.defaults.codex.model}"}
        -c ${lib.escapeShellArg "model_reasoning_effort=${builtins.toJSON team.defaults.codex.effort}"}
      )
      for arg in "$@"; do
        case "$arg" in
          --) break ;;
          -p|--profile|--profile=*|-p?*) defaults=(); break ;;
        esac
      done
      exec ${pkgs-unstable.codex}/bin/codex \
        "''${defaults[@]}" \
        ${lib.optionalString proxied ''
        -c 'model_provider="proxy"' \
        -c 'model_providers.proxy.name="Local Proxy"' \
        -c 'model_providers.proxy.base_url="http://localhost:1337/v1"' \
        ''}"$@"
    '';
  };
  codex = codexWrapper "codex" false;
  codex-proxied = codexWrapper "codex-proxied" true;

  # The Claude Codex plugin hardcodes `codex app-server` / `codex --version`.
  # Shadow it only inside claude-proxied, never in a normal shell.
  codex-proxied-shim = pkgs.runCommand "codex-proxied-shim" { } ''
    mkdir -p "$out/bin"
    ln -s ${codex-proxied}/bin/codex-proxied "$out/bin/codex"
  '';

  claudeWrapper = name: proxied:
    let
      routing = team.defaults.${if proxied then "claudeProxied" else "claude"};
      # Substitute the contents of a shell single-quoted literal, not an argument.
      agents = lib.replaceStrings [ "'" ] [ "'\\''" ]
        (if proxied then renderers.claudeProxiedAgents else "");
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = lib.optional proxied codex-proxied-shim;
      text = ''
        # shellcheck source=/dev/null
        source ${tempEnv} claude
      '' + lib.optionalString proxied ''
        export ANTHROPIC_BASE_URL="http://localhost:1337"
        export ANTHROPIC_API_KEY="dummy"
      '' + lib.replaceStrings
        [ "@claude@" "@model@" "@effort@" "@agents@" ]
        [ "${pkgs-unstable.claude-code}/bin/claude" routing.model routing.effort agents ]
        (builtins.readFile ./claude-cli.sh);
    };

  copilot = pkgs.symlinkJoin {
    name = "github-copilot-cli-wrapped";
    paths = [ pkgs-unstable.github-copilot-cli ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/copilot \
        --run ${lib.escapeShellArg "source ${tempEnv} copilot"} \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [
          pkgs.libsecret
          pkgs.glib
          pkgs.stdenv.cc.cc.lib
          pkgs.openssl
        ]}"
    '';
  };
in
{
  packages = [
    codex
    codex-proxied
    (claudeWrapper "claude" false)
    (claudeWrapper "claude-proxied" true)
    copilot
    pkgs.nodejs_24
  ];
}
