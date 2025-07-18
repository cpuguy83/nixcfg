{ ... }:

{
  nixpkgs.overlays = [
    (import ./vscode.nix)
  ];
}


