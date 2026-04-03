{
  inputs,
  pkgs-unstable,
  ...
}:
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
    (import ./vscode.nix)
    (import ./linux-entra-sso-host.nix)
    (import ./linux-entra-sso-host-mine.nix)
    (import ./hyprtasking.nix { inherit inputs pkgs-unstable; })
    (final: _prev: {
      opencode =
        (inputs.opencode.packages.${final.stdenv.hostPlatform.system}.opencode).overrideAttrs
          (oldAttrs: {
            node_modules = oldAttrs.node_modules.overrideAttrs {
              outputHash = "sha256-C7y5FMI1pGEgMw/vcPoBhK9tw5uGg1bk0gPXPUUVhgU=";
            };
          });
      opencode-desktop = inputs.opencode.packages.${final.stdenv.hostPlatform.system}.desktop;
      # (inputs.opencode.packages.${final.stdenv.hostPlatform.system}.opencode-desktop).overrideAttrs
      #   (oldAttrs: {
      #     node_modules = oldAttrs.node_modules.overrideAttrs {
      #       outputHash = "sha256-C7y5FMI1pGEgMw/vcPoBhK9tw5uGg1bk0gPXPUUVhgU=";
      #     };
      #   });
      hyprland = pkgs-unstable.hyprland;
      hyprlandPlugins = pkgs-unstable.hyprlandPlugins;
      ghostty = inputs.ghostty.packages.${final.stdenv.hostPlatform.system}.default;
      azure-cli = pkgs-unstable.azure-cli;
    })
  ];
}
