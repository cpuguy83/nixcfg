# Go implementation of linux-entra-sso native messaging host
# Works with microsoft-identity-broker 2.0.4+ (which removed D-Bus introspection)
{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "linux-entra-sso-host-mine";
  version = "1.0.0-mine";

  src = ../modules/home/linux-entra-sso-host;

  vendorHash = "sha256-WUTGAYigUjuZLHO1YpVhFSWpvULDZfGMfOXZQqVYAfs=";

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

  meta = with lib; {
    description = "Go implementation of linux-entra-sso native messaging host (works with broker 2.0.4+)";
    license = licenses.mpl20;
    platforms = platforms.linux;
  };
}
