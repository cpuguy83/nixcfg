{
  pkgs,
  pkgs-unstable,
  config,
  lib,
  inputs,
  ...
}:

with lib;
let
  cfg = config.mine.msft-corp;

  # NixOS is not a supported OS for Intune and this is part of the compliance
  # checks. This is a workaround to make it look like we are running Ubuntu.
  spoofedOSRelease = pkgs.writeText "intune-fake-os-release" ''
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

in
{
  imports = [
    inputs.azurevpnclient.nixosModules.azurevpnclient
  ];

  config = mkIf cfg.enable {
    # Make sure that the unstable channel is used for these packages
    # I think this is necessary because `services.intune.enable` is referencing
    # the stable channel otherwise.
    #
    # Unstable is needed to pick up a few fixes that are not currently in stable
    # such that stable is non-functional.
    nixpkgs.overlays = lib.mkAfter [
      (final: prev: {
        microsoft-identity-broker = pkgs-unstable.microsoft-identity-broker;
        intune-portal = pkgs-unstable.intune-portal;
      })

      (final: prev: {
        # microsoft-identity-broker = prev.microsoft-identity-broker.overrideAttrs (previousAttrs: rec {
        #   nativeBuildInputs = (previousAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
        #   postInstall = (previousAttrs.postInstall or "") + ''
        #     for bin in microsoft-identity-broker microsoft-identity-device-broker; do
        #       if [ -f "$out/bin/$bin" ]; then
        #         wrapProgram "$out/bin/$bin" \
        #           --set GIO_EXTRA_MODULES ${pkgs.glib-networking}/lib/gio/modules
        #       fi
        #     done
        #   '';
        # });

        intune-portal = prev.intune-portal.overrideAttrs (previousAttrs: rec {
          version = "1.2511.7-noble";

          src = pkgs.fetchurl {
            url = "https://packages.microsoft.com/ubuntu/24.04/prod/pool/main/i/intune-portal/intune-portal_${version}_amd64.deb";
            sha256 = "sha256-MHvAmkemx28ZNcVloFNxJ03YbxrgVPvB7OOMYR6Oyo8=";
          };

          nativeBuildInputs = (previousAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];

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

        microsoft-identity-broker = prev.microsoft-identity-broker.overrideAttrs (previousAttrs: rec {
          # postInstall = (previousAttrs.postInstall or "") + ''
          #   for bin in microsoft-identity-broker microsoft-identity-device-broker; do
          #     if [ -f "$out/bin/$bin" ]; then
          #       wrapProgram "$out/bin/$bin" \
          #         --set GIO_EXTRA_MODULES ${pkgs.glib-networking}/lib/gio/modules
          #     fi
          #   done
          # '';

          version = "2.5.0";
          src = pkgs.fetchurl {
            url = "https://packages.microsoft.com/ubuntu/24.04/prod/pool/main/m/microsoft-identity-broker/microsoft-identity-broker_${version}-noble_amd64.deb";
            sha256 = "sha256-zid9kjjz3mBfJFfiYUoqlIyQSsR041JN3Ib+JFSSEbE="; # 2.5.0
            # sha256 = "sha256-JbfmAwAFbjH8OaAoDcXdnD+Vvf4f17UATBTEpPTjBwM="; # 2.0.4
          };

          nativeBuildInputs =
            (previousAttrs.nativeBuildInputs or [ ])
            ++ (with pkgs; [
              dpkg
              makeWrapper
              zip
              autoPatchelfHook
            ]);

          buildInputs = with pkgs; [
            atk
            cairo
            curl
            dbus
            gdk-pixbuf
            glib
            gtk3
            harfbuzz
            libsecret
            libsoup_3
            libuuid
            openssl_3
            p11-kit
            pango
            stdenv.cc.cc.lib
            systemd
            webkitgtk_4_1
            xorg.libX11
            zlib
          ];

          buildPhase = ''
            runHook preBuild
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            # Copy usr/ contents
            if [ -d usr ]; then
              cp -a usr/. $out/
            fi
            # Copy binaries from /opt/ to /bin/ (2.0.4+ puts binaries in /opt/)
            if [ -d opt/microsoft/identity-broker/bin ]; then
              cp -a opt/microsoft/identity-broker/bin/* $out/bin/
            fi
            runHook postInstall
          '';

          postInstall = ''
            for bin in microsoft-identity-broker microsoft-identity-device-broker; do
              if [ -f "$out/bin/$bin" ]; then
                wrapProgram "$out/bin/$bin" \
                  --set GIO_EXTRA_MODULES "${pkgs.glib-networking}/lib/gio/modules" \
                  --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${pkgs.gst_all_1.gst-plugins-base}/lib/gstreamer-1.0:${pkgs.gst_all_1.gst-plugins-good}/lib/gstreamer-1.0" \
                  --set WEBKIT_DISABLE_COMPOSITING_MODE 1 \
                  --set WEBKIT_DISABLE_DMABUF_RENDERER 1
              fi
            done

            # Fix paths in systemd service (2.0.4+ uses /opt/microsoft/identity-broker/bin/)
            if [ -f "$out/lib/systemd/system/microsoft-identity-device-broker.service" ]; then
              substituteInPlace "$out/lib/systemd/system/microsoft-identity-device-broker.service" \
                --replace-quiet /usr/bin/microsoft-identity-device-broker "$out/bin/microsoft-identity-device-broker" \
                --replace-quiet /opt/microsoft/identity-broker/bin/microsoft-identity-device-broker "$out/bin/microsoft-identity-device-broker"
            fi
            if [ -f "$out/share/dbus-1/system-services/com.microsoft.identity.devicebroker1.service" ]; then
              substituteInPlace "$out/share/dbus-1/system-services/com.microsoft.identity.devicebroker1.service" \
                --replace-quiet /usr/bin/microsoft-identity-device-broker "$out/bin/microsoft-identity-device-broker" \
                --replace-quiet /opt/microsoft/identity-broker/bin/microsoft-identity-device-broker "$out/bin/microsoft-identity-device-broker"
            fi
            if [ -f "$out/share/dbus-1/services/com.microsoft.identity.broker1.service" ]; then
              substituteInPlace "$out/share/dbus-1/services/com.microsoft.identity.broker1.service" \
                --replace-quiet /usr/bin/microsoft-identity-broker "$out/bin/microsoft-identity-broker" \
                --replace-quiet /opt/microsoft/identity-broker/bin/microsoft-identity-broker "$out/bin/microsoft-identity-broker"
            fi
          '';
        });
      })
    ];

    services.gnome.glib-networking.enable = true;

    services.intune.enable = true;
    security.polkit.enable = true;
    security.rtkit.enable = true;

    environment.etc."ssl/certs/DigiCert_Global_Root_G2.pem".text = ''
      -----BEGIN CERTIFICATE-----
      MIIDjjCCAnagAwIBAgIQAzrx5qcRqaC7KGSxHQn65TANBgkqhkiG9w0BAQsFADBh
      MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
      d3cuZGlnaWNlcnQuY29tMSAwHgYDVQQDExdEaWdpQ2VydCBHbG9iYWwgUm9vdCBH
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

    # Min password requirements for intune
    security.pam.services.passwd.rules.password.pwquality = {
      control = lib.mkForce "requisite";
      modulePath = "${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so";
      # order BEFORE pam_unix.so
      order = config.security.pam.services.passwd.rules.password.unix.order - 10;
      settings = {
        # use_authtok = true;
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
      pkgs.intune-portal
      pkgs.microsoft-identity-broker
      libsecret
      linux-entra-sso-host-mine

      openconnect
      gpclient
      gpauth
      networkmanager-openconnect
      git-credential-manager

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

    systemd.user.services.intune-agent = {
      serviceConfig = {
        BindReadOnlyPaths = [
          "${spoofedOSRelease}:/etc/os-release"
        ];
      };
    };

    systemd.services.intune-daemon = {
      serviceConfig = {
        BindReadOnlyPaths = [
          "${spoofedOSRelease}:/etc/os-release"
        ];
      };
    };

    # Required because, at least for now, a script that MDM sends down to run
    # references `/bin/bash` directly instead of `/usr/bin/env bash`.
    # envfs is a workaround to make sure that the script can find bash.
    # services.envfs.enable = true;

    system.activationScripts.binbash = {
      deps = [ "binsh" ]; # Ensure /bin/sh is available first
      text = ''
        mkdir -m 0755 -p /bin
        ln -sfn ${pkgs.bash}/bin/bash /bin/bash
      '';
    };
  };
}
