{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.mine.msft-corp;
in
{
  config = lib.mkIf cfg.enable {
    home.file.".mozilla/native-messaging-hosts/linux_entra_sso.json" = {
      source = "${pkgs.linux-entra-sso-host}/lib/mozilla/native-messaging-hosts/linux_entra_sso.json";
    };
  };
}
