{ ... }:

{
  nixpkgs.overlays = [
    (import ./docker.nix)
    (import ./vscode.nix)
    (import ./qemu.nix)
  ];
}


