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
      coreutils # basename, cut
      gnugrep # grep
      gnused # sed
    ];
    text = builtins.readFile ./99-validate-dns;
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
      services.gnome.glib-networking.enable = true;
      security.polkit.enable = true;
      security.rtkit.enable = true;

      environment.etc."ssl/certs/DigiCert_Global_Root_G2.pem".text = ''
        -----BEGIN CERTIFICATE-----
        MIIDjjCCAnagAwIBAgIQAzrx5qcRqaC7KGSxHQn65TANBgkqhkiG9w0BAQsFADBh
        MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
        d3cuZGlnaUNlcnQuY29tMSAwHgYDVQQDExdEaWdpQ2VydCBHbG9iYWwgUm9vdCBH
        MjAeFw0xMzA4MDExMjAwMDBaFw0zODAxMTUxMjAwMDBaMGExCzAJBgNVBAYTAlVT
        MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
        b20xIDAeBgNVBAMTF0RpZ2lDZXJ0IEdsb2JhbCBSb290IEcyMIIBIjANBgkqhkiG
        9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuzfNNNx7a8myaJCtSnX/RrohCgiN9RlUyfuI
        2/Ou8jqJkTx65qsGGmvPrC3oXgkkRLpimn7Wo6h+4FR1IAWsULecYxpsMNzaHxmx
        1x7e/dfgy5SDN67sH0NO3Xss0r0upS/kqbitOtSZpLYl6ZtrAGCSYP9PIUkY92eQ
        q2EGnI/yuum06ZIya7XzV+hdG82MHauVBJVJ8zUtluNJbd134/tJS7SsVQepj5Wz
        tCO7TG1F8PapspUwtP1MVYwnSlcUfIKdzXOS0xZKBgyMUNGPHgm+F6HmIcr9g+UQ
        vIOlCsRnKPZzFBQ9RnbDhxSJITRNrw9FDKZJobq7nMWxM4MphQIDAQABo0IwQDAP
        BgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNVHQ4EFgQUTiJUIBiV
        5uNu5g/6+rkS7QYXjzkwDQYJKoZIhvcNAQELBQADggEBAGBnKJRvDkhj6zHd6mcY
        1Yl9PMWLSn/pvtsrF9+wX3N3KjITOYFnQoQj8kVnNeyIv/iPsGEMNKSuIEyExtv4
        NeF22d+mQrvHRAiGfzZ0JFrabA0UWTW98kndth/Jsw1HKj2ZL7tcu7XUIOGZX1NG
        Fdtom/DzMNU+MeKNhJ7jitralj41E6Vf8PlwUHBHQRFXGU7Aj64GxJUTFy8bJZ91
        8rGOmaFvE7FBcf6IKshPECBV1/MUReXgRPTqh5Uykw7+U0b6LJ3/iyK5S9kJRaTe
        pLiaWN0bfVKfjllDiIGknibVb63dDcY3fe0Dkhvld1927jyNxF1WW6LZZm6zNTfl
        MrY=
        -----END CERTIFICATE-----
      '';

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
