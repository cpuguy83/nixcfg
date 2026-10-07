{ lib, buildGoModule }:

buildGoModule {
  pname = "qs-launcher";
  version = "1";
  src = ./.;
  vendorHash = null;

  meta = {
    description = "Resident Quickshell launcher backend and request client";
    platforms = lib.platforms.linux;
    mainProgram = "qs-launcher";
  };
}
