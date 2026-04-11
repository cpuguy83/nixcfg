final: prev: {
  xdg-desktop-portal-hyprland = prev.xdg-desktop-portal-hyprland.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../patches/xdph/0001-feature-ui-improvements.patch
      ../patches/xdph/0002-add-icons.patch
      ../patches/xdph/0003-remove-share-token-ui.patch
      ../patches/xdph/0004-show-virtual-desktop.patch
      ../patches/xdph/0005-live-window-preview.patch
      ../patches/xdph/0006-screen-preview.patch
    ];
    postPatch = (old.postPatch or "") + ''
      substituteInPlace hyprland-share-picker/CMakeLists.txt \
        --replace-fail "/usr/share/wayland/wayland.xml" \
        "${final.wayland-scanner}/share/wayland/wayland.xml"
    '';
  });
}
