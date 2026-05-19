{
  inputs,
  pkgs-unstable,
  ...
}:
let
  opencodePackageJson = builtins.fromJSON (builtins.readFile "${inputs.opencode}/package.json");
in
{
  nixpkgs.overlays = [
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
      hyprland = pkgs-unstable.hyprland;
      hyprlandPlugins = pkgs-unstable.hyprlandPlugins;
      ghostty = inputs.ghostty.packages.${final.stdenv.hostPlatform.system}.default;
      azure-cli = pkgs-unstable.azure-cli;
      obs-studio = pkgs-unstable.obs-studio;
      obs-studio-plugins = pkgs-unstable.obs-studio-plugins;
      himmelblau = inputs.himmelblau.packages.${final.stdenv.hostPlatform.system};
      cider-2 = pkgs-unstable.cider-2;
    })
  ];
}
