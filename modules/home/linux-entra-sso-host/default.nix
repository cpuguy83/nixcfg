{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "linux-entra-sso-host";
  version = "1.0.0";

  src = ./.;

  vendorHash = "sha256-WUTGAYigUjuZLHO1YpVhFSWpvULDZfGMfOXZQqVYAfs=";

  meta = with lib; {
    description = "Go implementation of linux-entra-sso native messaging host";
    license = licenses.mpl20;
    platforms = platforms.linux;
  };

  postInstall = ''
    mkdir -p $out/lib/mozilla/native-messaging-hosts
    cat > $out/lib/mozilla/native-messaging-hosts/linux_entra_sso.json <<EOF
    {
      "name": "linux_entra_sso",
      "description": "Linux Entra SSO native messaging host",
      "path": "$out/bin/linux-entra-sso-host",
      "type": "stdio",
      "allowed_extensions": ["linux-entra-sso@example.com"]
    }
    EOF
  '';
}
