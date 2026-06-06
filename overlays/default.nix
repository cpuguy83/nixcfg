{ inputs
, pkgs-unstable
, copilotVersion
, ...
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
    (import ./vscode.nix)
    (import ./nix-unwrap.nix)
    (import ./linux-entra-sso-host.nix)
    (import ./linux-entra-sso-host-mine.nix)
    (import ./vekil.nix { inherit inputs; })
    (import ./hyprtasking.nix { inherit inputs pkgs-unstable; })
    (import ./github-copilot.nix { inherit inputs copilotVersion; })
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
      himmelblau = inputs.himmelblau.packages.${final.stdenv.hostPlatform.system};
      cider-2 = pkgs-unstable.cider-2;
    })
  ];
}
