{ lib, buildGoModule }:

buildGoModule {
  pname = "corpnet-vpn";
  version = "1";

  src = ./.;
  vendorHash = null;

  subPackages = [ "." ];

  checkPhase = ''
    runHook preCheck

    go test ./...

    runHook postCheck
  '';

  meta = {
    description = "Private corpnet route policy and silent profile refresh";
    platforms = lib.platforms.linux;
  };
}
