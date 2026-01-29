{ inputs, pkgs-unstable, ... }:

{
  nixpkgs.overlays = [
    inputs.waybar.overlays.default
    inputs.firefox-addons.overlays.default
    inputs.nixd.overlays.default
    inputs.rust-overlay.overlays.default
    (import ./opencode.nix { inherit inputs; })
    (import ./vscode.nix)
    (import ./linux-entra-sso-host.nix)
    (import ./linux-entra-sso-host-mine.nix)
    (import ./hyprtasking.nix { inherit inputs pkgs-unstable; })
  ];
}
