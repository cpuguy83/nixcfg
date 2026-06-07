{ pkgs
, pkgs-unstable
, config
, lib
, inputs
, ...
}:

with lib;
let
  cfg = config.mine.msft-corp;
  useIntune = cfg.authStack == "intune";
  useHimmelblau = cfg.authStack == "himmelblau";
  azureVpnUser = cfg.himmelblau.localUser;
  azureVpnUserConfig = config.users.users.${azureVpnUser} or { };
  azureVpnUserHome = azureVpnUserConfig.home or "/home/${azureVpnUser}";
  azureVpnUserGroup = azureVpnUserConfig.group or "users";
  azureVpnUserLogDir = "${azureVpnUserHome}/.config/microsoft-azurevpnclient/logs";
  azureVpnRootCert = pkgs.runCommand "azurevpn-digicert-global-root-g2.pem" { } ''
    sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' \
      ${pkgs.cacert.unbundled}/etc/ssl/certs/DigiCert_Global_Root_G2:33af1e6a711a9a0bb2864b11d09fae5.crt > "$out"
  '';

  # NixOS is not a supported OS for Intune's Linux compliance policy. Bind this
  # into the relevant service so the compliance check sees Ubuntu instead.
  spoofedOSRelease = pkgs.writeText "msft-fake-os-release" ''
    PRETTY_NAME="Ubuntu 24.04.3 LTS"
    NAME="Ubuntu"
    VERSION_ID="24.04"
    VERSION="24.04.3 LTS (Noble Numbat)"
    VERSION_CODENAME=noble
    ID=ubuntu
    ID_LIKE=debian
    HOME_URL="https://www.ubuntu.com/"
    SUPPORT_URL="https://help.ubuntu.com/"
    BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
    PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
    UBUNTU_CODENAME=noble
    LOGO=ubuntu-logo
  '';

  himmelblauConfig = pkgs.writeText "himmelblau.conf" ''
    [global]
    domain = microsoft.com
    pam_allow_groups = ${cfg.himmelblau.upn}
    enable_experimental_mfa = true
    enable_experimental_passwordless_fido = true
    apply_policy = true
    enable_experimental_intune_custom_compliance = true
    hsm_type = tpm_if_possible
    join_type = register
    user_map_file = /etc/himmelblau/user-map
    local_groups = users
    home_attr = CN
    home_alias = CN
    use_etc_skel = true
  '';

  vpnDNSDispatcher = pkgs.writeShellApplication {
    name = "99-validate-dns";
    runtimeInputs = with pkgs; [
      networkmanager # nmcli
      systemd # resolvectl
      dnsutils # dig
      gawk
      coreutils # basename, cut
      gnugrep # grep
      gnused # sed
    ];
    text = builtins.readFile ./99-validate-dns;
  };

  vpnDiagnostics = pkgs.writeShellApplication {
    name = "msft-vpn-diagnostics";
    runtimeInputs = with pkgs; [
      coreutils
      gpclient
      gnugrep
      networkmanager
      openconnect
      systemd
      xdg-utils
    ];
    text = ''
      export VPN_GATEWAY=${lib.escapeShellArg cfg.corpnet.gateway}
      export VPN_PROTOCOL=${lib.escapeShellArg cfg.corpnet.protocol}
      export VPN_REPORTED_OS=${lib.escapeShellArg cfg.corpnet.reportedOs}
      export AUTH_STACK=${lib.escapeShellArg cfg.authStack}
      export NM_DAEMON=${lib.escapeShellArg "${pkgs.networkmanager}/bin/NetworkManager"}
      export EXPECTED_BROWSER=${lib.escapeShellArg cfg.corpnet.browserDesktopFile}

      exec ${pkgs.bash}/bin/bash ${./msft-vpn-diagnostics.sh} "$@"
    '';
  };

  commonHimmelblauServiceConfig = {
    Type = "notify";
    UMask = "0027";
    NoNewPrivileges = true;
    PrivateDevices = true;
    ProtectHostname = true;
    ProtectClock = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    MemoryDenyWriteExecute = true;
  };
in
{
  imports = [
    inputs.azurevpnclient.nixosModules.azurevpnclient
  ];

  config = mkIf cfg.enable (mkMerge [
    {
      networking.networkmanager.dns = lib.mkDefault "systemd-resolved";
      services.resolved.enable = lib.mkDefault true;

      services.gnome.glib-networking.enable = true;
      security.polkit.enable = true;
      security.rtkit.enable = true;

      environment.etc."ssl/certs/DigiCert_Global_Root_G2.pem".source = azureVpnRootCert;

      environment.etc."NetworkManager/dispatcher.d/99-validate-dns" = {
        source = "${vpnDNSDispatcher}/bin/99-validate-dns";
        mode = "0755";
      };

      # Min password requirements for corporate compliance.
      security.pam.services.passwd.rules.password.pwquality = {
        control = lib.mkForce "requisite";
        modulePath = "${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so";
        order = config.security.pam.services.passwd.rules.password.unix.order - 10;
        settings = {
          shadowretry = 3;
          minlen = 12;
          difok = 6;
          dcredit = -1;
          ucredit = -1;
          ocredit = -1;
          lcredit = -1;
          enforce_for_root = true;
        };
      };

      environment.systemPackages = with pkgs; [
        vpnDiagnostics

        libsecret

        openconnect
        gpclient
        gpauth
        networkmanager-openconnect
        git-credential-manager

        opensc
        pcsc-tools

        mokutil
        efitools
        dmidecode
        wget
        gnutar
        gawk
        gnugrep
        coreutils
        util-linux
        procps
        gzip
        realm
      ];

      programs.azurevpnclient.enable = true;
      services.pcscd.enable = true;

      # Azure VPN Client writes diagnostics to this hard-coded path and opens it
      # from Settings -> Show Logs Directory, but the Linux client writes its UI
      # log under the user's config directory.
      systemd.tmpfiles.rules = [
        "d /var/log/azurevpnclient 0770 root ${config.programs.azurevpnclient.polkitGroup} -"
        "d ${azureVpnUserLogDir} 0755 ${azureVpnUser} ${azureVpnUserGroup} -"
        "L /var/log/azurevpnclient/AzureVPNClientUI.log - - - - ${azureVpnUserLogDir}/AzureVPNClientUI.log"
      ];

      # Register OpenSC PKCS#11 module with p11-kit so all PKCS#11-aware
      # applications (browsers, curl, etc.) can discover YubiKey PIV certs.
      environment.etc."pkcs11/modules/opensc.module".text = ''
        module: ${pkgs.opensc}/lib/opensc-pkcs11.so
      '';
    }

    (mkIf useIntune {
      # Make sure that the unstable channel is used for these packages. Unstable
      # is needed to pick up fixes that are not currently in stable.
      nixpkgs.overlays = lib.mkAfter [
        (final: prev: {
          intune-portal = pkgs-unstable.intune-portal.overrideAttrs (previousAttrs: rec {
            version = "1.2603.31";
            src = pkgs.fetchurl {
              url = "https://packages.microsoft.com/ubuntu/24.04/prod/pool/main/i/intune-portal/intune-portal_${version}-noble_amd64.deb";
              sha256 = "sha256-0braaXnRa04CUQdJx0ZFwe5qfjsJNzTtGqaKQV5Z6Yw=";
            };

            nativeBuildInputs = previousAttrs.nativeBuildInputs ++ [
              pkgs.makeWrapper
            ];

            postInstall = (previousAttrs.postInstall or "") + ''
              for bin in intune-portal intune-agent intune-daemon; do
                if [ -f "$out/bin/$bin" ]; then
                  wrapProgram "$out/bin/$bin" \
                    --set GIO_EXTRA_MODULES "${pkgs.glib-networking}/lib/gio/modules" \
                    --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${pkgs.gst_all_1.gst-plugins-base}/lib/gstreamer-1.0:${pkgs.gst_all_1.gst-plugins-good}/lib/gstreamer-1.0" \
                    --set WEBKIT_DISABLE_COMPOSITING_MODE 1 \
                    --set WEBKIT_DISABLE_DMABUF_RENDERER 1
                fi
              done
            '';
          });

          microsoft-identity-broker =
            pkgs-unstable.microsoft-identity-broker.overrideAttrs
              (previousAttrs: rec {
                version = "2.5.2";
                src = pkgs.fetchurl {
                  url = "https://packages.microsoft.com/ubuntu/24.04/prod/pool/main/m/microsoft-identity-broker/microsoft-identity-broker_${version}-noble_amd64.deb";
                  sha256 = "sha256-t5XP85ar16Et3fIp+Ia5KlD9fYwzbxHlcUlliseVTIk=";
                };

                nativeBuildInputs = previousAttrs.nativeBuildInputs ++ [
                  pkgs.makeWrapper
                ];

                postInstall = previousAttrs.postInstall + ''
                  for bin in microsoft-identity-broker microsoft-identity-device-broker; do
                    if [ -f "$out/bin/$bin" ]; then
                      wrapProgram "$out/bin/$bin" \
                        --set GIO_EXTRA_MODULES "${pkgs.glib-networking}/lib/gio/modules" \
                        --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${pkgs.gst_all_1.gst-plugins-base}/lib/gstreamer-1.0:${pkgs.gst_all_1.gst-plugins-good}/lib/gstreamer-1.0" \
                        --set WEBKIT_DISABLE_COMPOSITING_MODE 1 \
                        --set WEBKIT_DISABLE_DMABUF_RENDERER 1
                    fi
                  done
                '';
              });
        })
      ];

      services.intune.enable = true;

      environment.systemPackages = with pkgs; [
        intune-portal
        pkgs.microsoft-identity-broker
        linux-entra-sso-host-mine
      ];

      systemd.user.services.intune-agent.serviceConfig.BindReadOnlyPaths = [
        "${spoofedOSRelease}:/etc/os-release"
      ];

      systemd.services.intune-daemon.serviceConfig.BindReadOnlyPaths = [
        "${spoofedOSRelease}:/etc/os-release"
      ];

      # Required because, at least for now, a script that MDM sends down to run
      # references `/bin/bash` directly instead of `/usr/bin/env bash`.
      system.activationScripts.binbash = {
        deps = [ "binsh" ];
        text = ''
          mkdir -m 0755 -p /bin
          ln -sfn ${pkgs.bash}/bin/bash /bin/bash
        '';
      };
    })

    (mkIf useHimmelblau {
      environment.etc."himmelblau/himmelblau.conf".source = himmelblauConfig;
      environment.etc."himmelblau/user-map".text = ''
        ${cfg.himmelblau.localUser}:${cfg.himmelblau.upn}
      '';

      environment.systemPackages = with pkgs; [
        pkgs.himmelblau.daemon
        pkgs.himmelblau.aad-tool
        pkgs.himmelblau.pam
        pkgs.himmelblau.sso
        pkgs.himmelblau.broker
      ];

      services.dbus.packages = [
        pkgs.himmelblau.broker
      ];

      systemd.tmpfiles.rules = [
        "d /etc/cron.d 0755 root root -"
        "d /etc/krb5.conf.d 0755 root root -"
        "d /var/spool/cron 0700 root root -"
      ];

      system.activationScripts.binbash = {
        deps = [ "binsh" ];
        text = ''
          mkdir -m 0755 -p /bin
          ln -sfn ${pkgs.bash}/bin/bash /bin/bash
        '';
      };

      systemd.services.cronie = {
        description = "Cronie daemon for Himmelblau Intune script policies";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.cronie}/bin/crond -n";
          Restart = "on-failure";
        };
      };

      security.pam.services.greetd.rules.auth.himmelblau-unseal = {
        order = config.security.pam.services.greetd.rules.auth.unix.order - 10;
        control = "optional";
        modulePath = "${pkgs.himmelblau.pam.lib}/lib/libpam_himmelblau.so";
        settings.try_unseal = true;
      };

      security.pam.services.login.rules.auth.himmelblau-unseal = {
        order = config.security.pam.services.login.rules.auth.unix.order - 10;
        control = "optional";
        modulePath = "${pkgs.himmelblau.pam.lib}/lib/libpam_himmelblau.so";
        settings.try_unseal = true;
      };

      # hyprlock unlock mirrors greetd/login: pam_unix authenticates with the local
      # password (which equals the Hello PIN per the user_map_file setup) while
      # himmelblau silently unseals the Hello secret. The hyprlock service itself is
      # declared in modules/nixos/hyprland/lockscreen.nix.
      security.pam.services.hyprlock.rules.auth.himmelblau-unseal = {
        order = config.security.pam.services.hyprlock.rules.auth.unix.order - 10;
        control = "optional";
        modulePath = "${pkgs.himmelblau.pam.lib}/lib/libpam_himmelblau.so";
        settings.try_unseal = true;
      };

      systemd.user.services.himmelblau-broker = {
        description = "Himmelblau Authentication Broker";
        serviceConfig = {
          Type = "dbus";
          BusName = "com.microsoft.identity.broker1";
          ExecStart = "${pkgs.himmelblau.broker}/bin/himmelblau_broker";
          Slice = "background.slice";
          TimeoutStopSec = 5;
          Restart = "on-failure";
          WatchdogSec = "120s";
        };
      };

      systemd.services.himmelblaud = {
        description = "Himmelblau Authentication Daemon";
        wants = [
          "chronyd.service"
          "ntpd.service"
          "network-online.target"
        ];
        before = [ "accounts-daemon.service" ];
        wantedBy = [
          "multi-user.target"
          "accounts-daemon.service"
        ];
        upholds = [ "himmelblaud-tasks.service" ];
        serviceConfig = commonHimmelblauServiceConfig // {
          ExecStart = "${pkgs.himmelblau.daemon}/bin/himmelblaud --config ${himmelblauConfig}";
          Restart = "on-failure";
          WatchdogSec = "120s";
          DynamicUser = "yes";
          CacheDirectory = "himmelblaud";
          CacheDirectoryMode = "0700";
          RuntimeDirectory = "himmelblaud";
          StateDirectory = "himmelblaud";
          FileDescriptorStoreMax = 1;
          FileDescriptorStorePreserve = true;
          PrivateTmp = true;
          PrivateDevices = false;
          BindReadOnlyPaths = [
            "${spoofedOSRelease}:/etc/os-release"
          ];
        };
      };

      systemd.services.himmelblaud-tasks = {
        description = "Himmelblau Local Tasks";
        bindsTo = [ "himmelblaud.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [
          pkgs.shadow
          pkgs.bash
        ];
        unitConfig.ConditionPathExists = "/var/run/himmelblaud/task_sock";
        serviceConfig = commonHimmelblauServiceConfig // {
          ExecStart = "${pkgs.himmelblau.daemon}/bin/himmelblaud_tasks";
          Restart = "on-failure";
          WatchdogSec = "120s";
          User = "root";
          CacheDirectory = [
            "nss-himmelblau"
            "himmelblau-policies"
          ];
          CapabilityBoundingSet = [
            "CAP_CHOWN"
            "CAP_FOWNER"
            "CAP_DAC_OVERRIDE"
            "CAP_DAC_READ_SEARCH"
            "CAP_SETUID"
            "CAP_SETGID"
          ];
          AmbientCapabilities = [
            "CAP_SETUID"
            "CAP_SETGID"
          ];
          ProtectSystem = "strict";
          ReadWritePaths = "/home /var/run/himmelblaud /tmp /etc/krb5.conf.d /etc /var/lib /var/cache/nss-himmelblau /var/cache/himmelblau-policies";
          BindReadOnlyPaths = [
            "${spoofedOSRelease}:/etc/os-release"
          ];
        };
      };
    })
  ]);
}
