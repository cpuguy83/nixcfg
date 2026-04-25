# vekil: proxy to use Claude, Gemini, or OpenAI-compatible clients with GitHub Copilot
{
  lib,
  buildGoModule,
  src,
}:

buildGoModule {
  pname = "vekil";
  version = "unstable";

  inherit src;

  vendorHash = "sha256-4/i8OptKfbjx2jm7SSVw9jXwjHt0idmxIZ6SKLBZvCw=";

  # Only build the main binary, skip the macOS menubar app
  subPackages = [ "." ];

  meta = with lib; {
    description = "Proxy to use Claude, Gemini, or OpenAI-compatible clients with GitHub Copilot";
    homepage = "https://github.com/sozercan/vekil";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "vekil";
  };
}
