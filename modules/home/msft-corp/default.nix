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

    home.packages = with pkgs; [
      pkgs-unstable.microsoft-edge

      (azure-cli.withExtensions [
        azure-cli-extensions.azure-devops
      ])
    ];

    # Register OpenSC PKCS#11 module in the NSS database used by Chromium-based
    # browsers (Edge) so they can access PIV certificates on the YubiKey.
    home.activation.setupPkcs11Nss = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.pki/nssdb"
      if [ ! -f "$HOME/.pki/nssdb/cert9.db" ]; then
        ${pkgs.nssTools}/bin/certutil -d sql:"$HOME/.pki/nssdb" -N --empty-password
      fi
      if ! ${pkgs.nssTools}/bin/modutil -dbdir sql:"$HOME/.pki/nssdb" -list 2>/dev/null | grep -q "OpenSC"; then
        ${pkgs.nssTools}/bin/modutil -dbdir sql:"$HOME/.pki/nssdb" -add "OpenSC PKCS#11" -libfile ${pkgs.opensc}/lib/opensc-pkcs11.so -force
      fi
    '';
  };
}
