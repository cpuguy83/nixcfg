{ pkgs
, inputs
, config
, ...
}:
let
  cfg = config.mine.msft-corp;
  azureVpnUser = cfg.himmelblau.localUser;
  azureVpnUserConfig = config.users.users.${azureVpnUser} or { };
  azureVpnUserHome = azureVpnUserConfig.home or "/home/${azureVpnUser}";
  azureVpnUserGroup = azureVpnUserConfig.group or "users";
  azureVpnUserLogDir = "${azureVpnUserHome}/.config/microsoft-azurevpnclient/logs";
  azureVpnRootCert = pkgs.runCommand "azurevpn-digicert-global-root-g2.pem" { } ''
    sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' \
      ${pkgs.cacert.unbundled}/etc/ssl/certs/DigiCert_Global_Root_G2:33af1e6a711a9a0bb2864b11d09fae5.crt > "$out"
  '';

in
{
  imports = [
    inputs.azurevpnclient.nixosModules.azurevpnclient
  ];

  programs.azurevpnclient.enable = true;

  # Azure VPN Client writes diagnostics to this hard-coded path and opens it
  # from Settings -> Show Logs Directory, but the Linux client writes its UI
  # log under the user's config directory.
  systemd.tmpfiles.rules = [
    "d /var/log/azurevpnclient 0770 root ${config.programs.azurevpnclient.polkitGroup} -"
    "d ${azureVpnUserLogDir} 0755 ${azureVpnUser} ${azureVpnUserGroup} -"
    "L /var/log/azurevpnclient/AzureVPNClientUI.log - - - - ${azureVpnUserLogDir}/AzureVPNClientUI.log"
    # Holds the unmanaged corpnet-routes.txt the vpnc-script reads as root.
    "d /etc/msft-vpn 0755 root root -"
  ];

  environment.etc."ssl/certs/DigiCert_Global_Root_G2.pem".source = azureVpnRootCert;
}
