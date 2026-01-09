{ inputs, ... }:

{
  nixpkgs.overlays = [
    inputs.waybar.overlays.default
    inputs.firefox-addons.overlays.default
    inputs.nixd.overlays.default
    inputs.rust-overlay.overlays.default
    (import ./vscode.nix)
    (import ./linux-entra-sso-host.nix)
    (import ./linux-entra-sso-host-mine.nix)
  ];
}
