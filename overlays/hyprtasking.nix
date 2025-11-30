{ inputs }:
(
  final: prev:
  let
    system = final.stdenv.hostPlatform.system;
    hyprlandPkg = inputs.hyprland.packages.${system}.hyprland;
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

      buildInputs = [
        hyprlandPkg
      ]
      ++ (with final; [
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
      ])
      ++ (with inputs.hyprland.inputs; [
        # Include hyprland ecosystem libraries
        hyprutils.packages.${system}.hyprutils
        hyprlang.packages.${system}.hyprlang
        hyprgraphics.packages.${system}.hyprgraphics
        aquamarine.packages.${system}.aquamarine
      ]);

      meta = with final.lib; {
        description = "Workspace management plugin for Hyprland";
        homepage = "https://github.com/raybbian/hyprtasking";
        license = licenses.bsd3;
        platforms = platforms.linux;
      };
    };
  }
)
