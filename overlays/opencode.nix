{ inputs }:
final: _prev:
let
  system = final.stdenv.hostPlatform.system;
in
{
  opencode = inputs.opencode.packages.${system}.opencode;
  opencode-desktop = inputs.opencode.packages.${system}.desktop;
}
