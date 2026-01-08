{
  lib,
  stdenv,
  fetchFromGitHub,
  python3,
  makeWrapper,
  wrapGAppsNoGuiHook,
  glib,
  gobject-introspection,
}:

let
  pythonEnv = python3.withPackages (
    ps: with ps; [
      pydbus
      pygobject3
    ]
  );
in

stdenv.mkDerivation rec {
  pname = "linux-entra-sso-host";
  version = "1.7.2"; # update as needed

  nativeBuildInputs = [
    makeWrapper
    wrapGAppsNoGuiHook
  ];
  buildInputs = [
    pythonEnv
    glib
    gobject-introspection
  ];

  src = fetchFromGitHub {
    owner = "siemens";
    repo = "linux-entra-sso";
    rev = "v${version}";
    sha256 = "sha256-zBeFNTAluanKWTQPgZ/ul6qQoIKSbvsjH97X1l3BBVc=";
  };

  buildPhase = "true"; # No build step needed

  installPhase = ''
    install -Dm755 linux-entra-sso.py $out/libexec/linux-entra-sso/linux-entra-sso.py

    substituteInPlace $out/libexec/linux-entra-sso/linux-entra-sso.py \
      --replace-fail "0.0.0-dev" "${version}" \
      --replace-quiet "#!/usr/bin/python3" "#!${python3}/bin/python3"

    makeWrapper $out/libexec/linux-entra-sso/linux-entra-sso.py $out/bin/linux-entra-sso \
      --argv0 "$out/libexec/linux-entra-sso/linux-entra-sso.py" \
      --add-flags "$out/libexec/linux-entra-sso/linux-entra-sso.py" \
      --prefix PYTHONPATH : "${pythonEnv}/${python3.sitePackages}" \
      --set GI_TYPELIB_PATH "${glib}/share/gir-1.0:${gobject-introspection}/share/gir-1.0" # Make sure this path is correct

    install -Dm644 platform/firefox/linux_entra_sso.json \
      $out/lib/mozilla/native-messaging-hosts/linux_entra_sso.json

    substituteInPlace $out/lib/mozilla/native-messaging-hosts/linux_entra_sso.json \
      --replace "/usr/local/lib/linux-entra-sso/linux-entra-sso.py" \
                "$out/bin/linux-entra-sso"
  '';

  meta = with lib; {
    description = "Siemens linux-entra-sso native messaging host for firefox";
    license = licenses.mpl20;
  };
}
