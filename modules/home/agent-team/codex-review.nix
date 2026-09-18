{ lib, pkgs, codexPackage, cfg, routing }:

# A deliberately rigid front end for `codex exec`.
#
# The Claude agents that call this never compose a codex command line. They get
# four fixed shapes -- `brief-dir`, `new-brief`, `design <brief>` and
# `final <repo>` -- and everything else about the invocation is decided here.
# Prompt text always travels over stdin, so no model, user, or repository text
# is ever interpolated into a command.
#
# The brief path is not a free parameter. `new-brief` issues a name under a
# private 0700 directory the wrapper owns, and `design` accepts only that shape,
# so the wrapper cannot be talked into reading or deleting an unrelated file.
#
# Codex has no standalone credentials on this host, so the call is routed
# through the same local proxy `codex-proxied` uses, with user configuration
# switched off so per-project trust levels and MCP servers cannot leak in. If
# the proxy is down the wrapper says so explicitly, because silence from a
# review tool is too easy to mistake for approval.

let
  tempEnv = import ./temp-env.nix { inherit pkgs; };

  designPreamble = pkgs.writeText "codex-design-review-preamble" ''
    You are an independent design reviewer. Another engineering agent produced
    the brief below before writing any code. Do not write or modify files.

    Reply with these sections, omitting any that are genuinely empty:

    BLOCKING: design flaws that will produce incorrect behaviour.
    RISKS: consequences the brief has not accounted for.
    SIMPLER: places where the design is more complex than the requirement.
    QUESTIONS: ambiguities that must be resolved before implementation.
    ASSESSMENT: one line, either "proceed" or "revise".

    Judge the design on its merits. Do not assume the brief's conclusions are
    correct, and say so plainly when the stated requirement and the proposed
    design have drifted apart.
  '';

  finalPreamble = pkgs.writeText "codex-final-review-preamble" ''
    You are an independent adversarial reviewer. Review the uncommitted changes
    in this repository working tree. Start with `git status` and `git diff`,
    including staged changes. Do not write or modify files, and do not run tests
    that mutate the tree.

    Assume the author and their primary reviewer share blind spots. Look for
    counterexamples, incorrect assumptions, ordering and concurrency hazards,
    unsafe trust boundaries, error paths that silently succeed, and cases where
    validation can pass while the change is still wrong.

    Reply with these sections, omitting any that are genuinely empty:

    BLOCKING: defects that must be fixed, each with file, line, and the concrete
    scenario that triggers it.
    CONCERNS: real but non-blocking problems.
    VERIFICATION GAPS: behaviour the existing checks do not actually prove.
    ASSESSMENT: one line, either "ship" or "fix first".

    Report only findings you can support from the diff. Distinguish a
    demonstrated defect from a speculative one.
  '';

  substitute = replacements: file:
    lib.replaceStrings
      (map (r: r.from) replacements)
      (map (r: r.to) replacements)
      (builtins.readFile file);
in
rec {
  review = pkgs.writeShellApplication {
    name = "codex-team-review";

    runtimeInputs = [
      codexPackage
      pkgs.coreutils
      pkgs.findutils
    ];

    text = ''
      # shellcheck source=/dev/null
      source ${tempEnv} codex
    '' + substitute [
      { from = "@baseUrl@"; to = cfg.baseUrl; }
      { from = "@codex@"; to = "${codexPackage}/bin/codex"; }
      { from = "@model@"; to = routing.model; }
      { from = "@effort@"; to = routing.effort; }
      { from = "@timeoutSeconds@"; to = toString cfg.timeoutSeconds; }
      { from = "@maxBriefBytes@"; to = toString cfg.maxBriefBytes; }
      { from = "@maxBriefAgeSeconds@"; to = toString cfg.maxBriefAgeSeconds; }
      { from = "@designPreamble@"; to = "${designPreamble}"; }
      { from = "@finalPreamble@"; to = "${finalPreamble}"; }
    ] ./codex-review.sh;
  };

  guard = pkgs.writeShellApplication {
    name = "codex-team-review-guard";

    runtimeInputs = [ pkgs.jq ];

    text = substitute [
      { from = "@wrapper@"; to = "${review}/bin/codex-team-review"; }
    ] ./codex-review-guard.sh;
  };
}
