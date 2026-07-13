{
  inputs,
  pkgs-unstable,
  copilotVersion,
  ...
}:
let
  opencodePackageJson = builtins.fromJSON (builtins.readFile "${inputs.opencode}/package.json");
in
{
  nixpkgs.overlays = [
    (final: prev: {
      waybar = prev.waybar.override {
        runTests = false;
      };
    })
    inputs.waybar.overlays.default
    (
      final: prev:
      let
        libMozilla = import "${inputs.firefox-addons}/../../lib/mozilla.nix" { lib = final.lib; };
        buildMozillaXpiAddon = libMozilla.mkBuildMozillaXpiAddon {
          inherit (final) fetchurl stdenv;
        };
      in
      {
        firefox-addons = final.callPackage "${inputs.firefox-addons}" {
          inherit buildMozillaXpiAddon;
        };
      }
    )
    inputs.nixd.overlays.default
    inputs.rust-overlay.overlays.default
    inputs.handy-mine.overlays.default
    inputs.calbar.overlays.default
    (import ./mactahoe-gtk-theme.nix)
    (import ./vscode.nix { inherit inputs; })
    (import ./nix-unwrap.nix)
    (import ./linux-entra-sso-host.nix)
    (import ./linux-entra-sso-host-mine.nix)
    (import ./vekil.nix { inherit inputs; })
    (import ./hyprtasking.nix { inherit inputs pkgs-unstable; })
    (import ./github-copilot.nix { inherit inputs copilotVersion; })
    (import ./lmstudio.nix { inherit pkgs-unstable; })
    (final: _prev: {
      opencode =
        (inputs.opencode.packages.${final.stdenv.hostPlatform.system}.opencode).overrideAttrs
          (oldAttrs: {
            postConfigure = (oldAttrs.postConfigure or "") + ''
              substituteInPlace package.json \
                --replace-fail '"packageManager": "${opencodePackageJson.packageManager}"' \
                '"packageManager": "bun@${pkgs-unstable.bun.version}"'
            '';
          });
      ghostty = inputs.ghostty.packages.${final.stdenv.hostPlatform.system}.default;
      # Patch the himmelblau broker so MSAL's account-picker interactive flow
      # (account: null / empty username, e.g. `workiq ask`) works end-to-end:
      #   * fall back to the caller's enrolled account instead of erroring when
      #     MSAL sends a null account, and
      #   * rewrite the redirect URI to the WAM broker redirect so PRT
      #     redemption for third-party public-client apps doesn't hit
      #     AADSTS50011.
      # Rebuilding from the patched source only recompiles the broker crate;
      # other crates are content-addressed and reused from cache.
      himmelblau =
        let
          system = final.stdenv.hostPlatform.system;
          patchedSrc = final.applyPatches {
            name = "himmelblau-src-broker-interactive-auth";
            src = inputs.himmelblau;
            patches = [ ../patches/himmelblau-broker-interactive-auth.patch ];
          };
          himmelblauPkgs =
            (import patchedSrc {
              inherit system;
              pkgs = final;
            }).packages;
        in
        builtins.removeAttrs himmelblauPkgs [ "recurseForDerivations" ];
      cider-2 = pkgs-unstable.cider-2;
      signal-desktop = pkgs-unstable.signal-desktop;
      discord = pkgs-unstable.discord;
      legcord = pkgs-unstable.legcord;
    })
  ];
}
