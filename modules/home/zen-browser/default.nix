{
  pkgs,
  inputs,
  lib,
  ...
}:

{
  home.sessionVariables.MOZ_ENBALE_WAYLAND = "1";

  imports = [
    inputs.zen-browser.homeModules.default
  ];

  programs.zen-browser = lib.mkMerge [
    (import ../firefox/common.nix { inherit pkgs; })
    {
      enable = true;

      profiles.default.settings = {
        "zen.theme.content-element-separation" = 0;
        "zen.view.drag-window-from-content" = false;
      };
    }
  ];
}
