{ inputs, pkgs-unstable }:
final: prev: {
  hyprtasking = pkgs-unstable.gcc14Stdenv.mkDerivation {
    pname = "hyprtasking";
    version = "0.1";
    src = inputs.hyprtasking; # flake input used as source only
    nativeBuildInputs = [
      final.meson
      final.ninja
    ]
    ++ pkgs-unstable.hyprland.nativeBuildInputs;
    buildInputs = [ pkgs-unstable.hyprland ] ++ pkgs-unstable.hyprland.buildInputs;
  };
}
