{ lib
, buildGoModule
, fetchFromGitHub
,
}:

buildGoModule {
  pname = "zapp";
  version = "0-unstable-2024-10-28";

  src = fetchFromGitHub {
    owner = "cpuguy83";
    repo = "zapp";
    rev = "b0a18cbb86ca460d3365c859688ce7ab4746e101";
    hash = "sha256-2YzVJlnbizPNfi1GmARIVxRHdcvnJtiFIGHds6schFQ=";
  };

  vendorHash = "sha256-724U6IW6qkob9MENNT9E9WxC2msj2iLlcgExTFEr1pE=";
  subPackages = [ "." ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/zapp" --help
    runHook postInstallCheck
  '';

  meta = {
    description = "Interact with Docker and OCI registry objects";
    homepage = "https://github.com/cpuguy83/zapp";
    # Upstream does not declare a license.
    license = lib.licenses.unfree;
    mainProgram = "zapp";
  };
}
