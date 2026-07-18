# vekil: proxy to use Claude, Gemini, or OpenAI-compatible clients with GitHub Copilot
{ lib
, buildGoModule
, src
,
}:

buildGoModule {
  pname = "vekil";
  version = "unstable";

  inherit src;

  # Recomputed by ./update.sh; stored in a sibling file so the bump is a
  # one-line data change rather than an edit to this derivation.
  vendorHash = lib.trim (builtins.readFile ./vendor.sha256);

  # Build both the root CLI (launch/login/server -> $out/bin/vekil) and the
  # tray app (cmd/menubar -> $out/bin/menubar, renamed below to vekil-menubar).
  subPackages = [ "." "cmd/menubar" ];

  postInstall = ''
        mv "$out/bin/menubar" "$out/bin/vekil-menubar"

        install -Dm644 assets/macos/Vekil.png \
          "$out/share/icons/hicolor/256x256/apps/vekil.png"

        mkdir -p "$out/share/applications"
        cat > "$out/share/applications/vekil.desktop" <<'EOF'
    [Desktop Entry]
    Name=Vekil
    Comment=Local AI proxy tray app
    Exec=vekil-menubar
    Icon=vekil
    Terminal=false
    Type=Application
    Categories=Network;Utility;
    StartupNotify=false
    EOF
  '';

  meta = with lib; {
    description = "Proxy to use Claude, Gemini, or OpenAI-compatible clients with GitHub Copilot";
    homepage = "https://github.com/sozercan/vekil";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "vekil";
  };
}
