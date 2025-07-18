{  lib, stdenv, fetchFromGitHub, python3, makeWrapper }:

let
  pythonEnv = python3.withPackages (ps: with ps; [ pydbus pygobject3 ]);
in

stdenv.mkDerivation rec {
  pname = "linux-entra-sso-host";
  version = "1.4.0"; # update as needed

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ pythonEnv ];

  src = fetchFromGitHub {
    owner = "siemens";
    repo = "linux-entra-sso";
    rev = "v${version}";
    sha256 = "sha256-NtqnuG6ChWNNQkyM4DJpWMa79UDsALcO7ZM+W6a36hE=";
  };

  buildPhase = "true"; # No build step needed

  installPhase = ''
    install -Dm755 linux-entra-sso.py $out/libexec/linux-entra-sso/linux-entra-sso.py

    substituteInPlace $out/libexec/linux-entra-sso/linux-entra-sso.py \
      --replace "0.0.0-dev" "${version}" \
      --replace "#!/usr/bin/python3" "#!${python3}/bin/python3"

    makeWrapper ${python3}/bin/python3 $out/bin/linux-entra-sso \
      --add-flags "$out/libexec/linux-entra-sso/linux-entra-sso.py" \
      --prefix PYTHONPATH : "${pythonEnv}/${python3.sitePackages}"

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
