{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  ...
}:
let
  cfg = config.mine.msft-corp;
in
{
  config = lib.mkIf cfg.enable {
    home.file.".mozilla/native-messaging-hosts/linux_entra_sso.json" = {
      source = "${pkgs.linux-entra-sso-host-mine}/lib/mozilla/native-messaging-hosts/linux_entra_sso.json";
    };

    home.packages = [
      pkgs-unstable.microsoft-edge
      # Teams PWA still references the old microsoft-edge-stable binary name
      (pkgs.writeShellScriptBin "microsoft-edge-stable" ''
        exec ${pkgs-unstable.microsoft-edge}/bin/microsoft-edge "$@"
      '')
    ];
  };
}
