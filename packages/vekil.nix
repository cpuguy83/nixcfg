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

  vendorHash = "sha256-4/i8OptKfbjx2jm7SSVw9jXwjHt0idmxIZ6SKLBZvCw=";

  subPackages = [ "cmd/menubar" ];

  postInstall = ''
        mv "$out/bin/menubar" "$out/bin/vekil"

        install -Dm644 assets/macos/Vekil.png \
          "$out/share/icons/hicolor/256x256/apps/vekil.png"

        mkdir -p "$out/share/applications"
        cat > "$out/share/applications/vekil.desktop" <<'EOF'
    [Desktop Entry]
    Name=Vekil
    Comment=Local AI proxy tray app
    Exec=vekil
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
