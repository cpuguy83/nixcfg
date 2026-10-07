{ lib
, stdenv
, fetchFromGitHub
, python3
, makeWrapper
, wrapGAppsNoGuiHook
, glib
, gobject-introspection
,
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
  version = "1.13.0";

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
    sha256 = "sha256-zkdS7dsIUgIoj6g+to1++K655nUXyE6uxkx6uIoHh6w=";
  };

  buildPhase = "true"; # No build step needed

  # The hook would otherwise wrap the .py in libexec, replacing it with a binary.
  dontWrapGApps = true;

  installPhase = ''
    install -Dm755 linux-entra-sso.py $out/libexec/linux-entra-sso/linux-entra-sso.py

    substituteInPlace $out/libexec/linux-entra-sso/linux-entra-sso.py \
      --replace-fail "0.0.0-dev" "${version}"

    install -Dm644 platform/firefox/linux_entra_sso.json \
      $out/lib/mozilla/native-messaging-hosts/linux_entra_sso.json

    substituteInPlace $out/lib/mozilla/native-messaging-hosts/linux_entra_sso.json \
      --replace-fail "/usr/local/lib/linux-entra-sso/linux-entra-sso" \
                     "$out/bin/linux-entra-sso"
  '';

  # gappsWrapperArgs is only populated once the fixup phase has started.
  postFixup = ''
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/linux-entra-sso \
      --add-flags "$out/libexec/linux-entra-sso/linux-entra-sso.py" \
      "''${gappsWrapperArgs[@]}"
  '';

  meta = with lib; {
    description = "Siemens linux-entra-sso native messaging host for firefox";
    license = licenses.mpl20;
  };
}
