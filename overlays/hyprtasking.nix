{ inputs }:
(final: prev:
let
  hyprlandPkg = inputs.hyprland.packages.${final.system}.hyprland;
in
{
  hyprtasking = final.gcc14Stdenv.mkDerivation {
    pname = "hyprtasking";
    version = "0.1";

    src = inputs.hyprtasking;

    nativeBuildInputs = with final; [
      pkg-config
      meson
      ninja
    ];

    buildInputs = [ hyprlandPkg ] ++ (with final; [
      # Include the specific dependencies from Hyprland that are needed
      pango
      cairo
      libdrm
      pixman
      wayland
      wayland-protocols
      libxkbcommon
      libinput
      mesa
      libglvnd
      xwayland
    ]) ++ (with inputs.hyprland.inputs; [
      # Include hyprland ecosystem libraries
      hyprutils.packages.${final.system}.hyprutils
      hyprlang.packages.${final.system}.hyprlang
      hyprgraphics.packages.${final.system}.hyprgraphics
      aquamarine.packages.${final.system}.aquamarine
    ]);

    meta = with final.lib; {
      description = "Workspace management plugin for Hyprland";
      homepage = "https://github.com/raybbian/hyprtasking";
      license = licenses.bsd3;
      platforms = platforms.linux;
    };
  };
})
