{ inputs, ... }:

{
  nixpkgs.overlays = [
    (import ./vscode.nix)
    (import ./hyprtasking.nix { inherit inputs; })
  ];
}
