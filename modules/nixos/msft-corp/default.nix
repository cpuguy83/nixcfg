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
  vpnUser = cfg.himmelblau.localUser;

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

  # Adds the corp split-tunnel routes to the corpnet GlobalProtect tunnel after it
  # connects. corpnet is brought up by standalone gpclient/openconnect (not
  # NetworkManager), so we hook openconnect's vpnc-script rather than an NM
  # dispatcher. This wrapper defers to the standard vpnc-script, then adds the
  # corp routes on connect. The route list itself is an unmanaged file (corp-
  # internal IP ranges, kept out of this repo) at /etc/msft-vpn/corpnet-routes.txt;
  # see ./corpnet-vpnc-script.sh for the command to (re)generate it. The script
  # runs as root under openconnect and reads the routes from that absolute path.
  corpnetVpncScript = pkgs.writeShellApplication {
    name = "corpnet-vpnc-script";
    runtimeInputs = with pkgs; [
      iproute2 # ip
      gnugrep
      gnused
      gawk
      coreutils # basename
      util-linux # logger (journal diagnostics)
    ];
    text = ''
      export CORPNET_BASE_VPNC_SCRIPT=${lib.escapeShellArg "${pkgs.vpnc-scripts}/bin/vpnc-script"}
      export CORPNET_ROUTES_FILE=${lib.escapeShellArg "/etc/msft-vpn/corpnet-routes.txt"}

      exec ${pkgs.bash}/bin/bash ${./corpnet-vpnc-script.sh} "$@"
    '';
  };

  # ExecStartPre/Post/ExecStopPost hook for corpnet-vpn(@).service (see
  # mkCorpnetVpnService below): writes each state transition to a stable,
  # world-readable path so the Quickshell Control Center panel (VpnState.qml)
  # can watch it via inotify instead of polling
  # (.copilot/plans/control-center.md §9.6/§10 I2).
  #
  # Deliberately a fixed /run path, not a RuntimeDirectory: a
  # RuntimeDirectory is torn down when the *owning* unit stops, and
  # corpnet-vpn.service / corpnet-vpn@.service are two different units that
  # both write here, so one stopping must not delete a path the other still
  # expects to exist. An inotify watch on a path that can vanish out from
  # under it is a well-known footgun; a path that is simply overwritten in
  # place, and always exists once anything has ever run, is not.
  #
  # The file is a change notifier only, never a data source — see
  # VpnState.qml's own comment for why its contents are never parsed back
  # into VPN state; `corpnet-vpn-indicator state` stays the one place that
  # formats gateway/region data. `STATE_FILE` is overridable so this can be
  # exercised against a scratch path instead of the real /run location.
  corpnetVpnStateHook = pkgs.writeShellScript "corpnet-vpn-state-hook" ''
    set -euo pipefail

    : "''${STATE_FILE:=/run/corpnet-vpn.state}"

    state="''${1:?usage: $0 <state> [region]}"
    region="''${2:-}"

    printf '%s %s\n' "$state" "$region" > "$STATE_FILE"
    chmod 0644 "$STATE_FILE"
  '';

  # gpclient's --os value (it expects "Windows"/"Mac"/"Linux"); map the short
  # corpnet.reportedOs the same way msft-vpn-diagnostics' gpclient_os() does.
  gpclientReportedOs =
    let
      o = cfg.corpnet.reportedOs;
    in
    if o == "win" || o == "Windows" then
      "Windows"
    else if o == "mac" || o == "Mac" then
      "Mac"
    else if o == "linux" || o == "Linux" then
      "Linux"
    else
      o;

  # Browser gpauth opens for SAML. Under the systemd service, gpauth inherits the
  # unit's minimal PATH (desktop_session_env reconstructs XDG/DBUS/Wayland from
  # the user's session but deliberately does NOT carry PATH), so gpclient's
  # --default-browser auto-detection finds neither xdg-open nor a browser and
  # fails silently. Pass an explicit browser binary instead: gpauth then spawns it
  # directly via `open` (Browser::Other), independent of PATH or xdg tooling. The
  # binary is the home-manager-installed browser in the user's per-user profile,
  # named after corpnet.browserDesktopFile.
  corpnetBrowserBin = "/etc/profiles/per-user/${vpnUser}/bin/${lib.removeSuffix ".desktop" cfg.corpnet.browserDesktopFile}";

  # The external-browser GlobalProtect auth flow (gpclient connect
  # --default-browser) ends by redirecting the browser to a
  # globalprotectcallback://<data> URL that must be handed back to the waiting
  # gpauth process. Upstream registers this scheme via gpgui's desktop entry, but
  # nixpkgs ships neither that entry nor a gpgui binary, so the browser has
  # nowhere to deliver the SAML cookie and gpauth hangs forever. gpclient itself
  # performs the hand-off: "gpclient launch-gui <url>" reads gpcallback.port and
  # writes the cookie to gpauth's local socket. Register it as the handler.
  gpCallbackHandler = pkgs.makeDesktopItem {
    name = "globalprotect-callback";
    desktopName = "GlobalProtect Callback Handler";
    exec = "${pkgs.gpclient}/bin/gpclient launch-gui %u";
    mimeTypes = [ "x-scheme-handler/globalprotectcallback" ];
    noDisplay = true;
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
      export VPN_VPNC_SCRIPT=${lib.escapeShellArg "${corpnetVpncScript}/bin/corpnet-vpnc-script"}

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

  # Shared definition for the corpnet VPN unit. `gateway` is the gpclient target
  # host and may embed the systemd `%i` specifier (used by the corpnet-vpn@
  # template so an instance name selects the region). `label` is a human-readable
  # gateway name for the unit description.
  mkCorpnetVpnService = { gateway, label }:
    let
      # Region for the /run/corpnet-vpn.state hooks below: the leading
      # dot-separated segment of `gateway`. For the bare unit `gateway` is
      # already a plain hostname (e.g.
      # "redmond.msftvpn-alt.ras.microsoft.com"), so this yields the same
      # short name `corpnet-vpn-indicator.sh`'s own `default_region()`
      # derives (`${DEFAULT_GATEWAY%%.*}`). For the `@` template `gateway` is
      # `%i.${gatewayDomain}`, so this yields the systemd specifier `%i`
      # literally — exactly what belongs in that unit's own Exec lines,
      # expanded per-instance by systemd itself. No region list to hardcode
      # either way.
      region = lib.head (lib.splitString "." gateway);
    in
    {
      description = "Microsoft corpnet GlobalProtect VPN (gpclient) — ${label}";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # If the server invalidates the session cookie (e.g. after a TLS drop the
      # gateway rejects the reconnect with "Cookie is no longer valid"),
      # openconnect cannot silently recover and gpclient exits non-zero. Restart
      # so it re-authenticates (fast/silent via the broker PRT). systemd does not
      # honor Restart= for an explicit `systemctl stop`, so the manual toggle
      # still tears the tunnel down cleanly. The start-limit caps how often a
      # persistent auth failure can relaunch the browser before the unit gives up.
      # (No --cookie-cache: with --as-gateway gpclient always does a fresh gateway
      # prelogin and never reads or writes the portal cookie cache, so caching it
      # would be dead config. A restart re-auths via browser SAML, which the
      # broker PRT makes fast.)
      startLimitIntervalSec = 600;
      startLimitBurst = 5;
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 10;
        Environment = [
          "TMPDIR=/tmp"
          "DOAS_USER=${vpnUser}"
        ];
        # /run/corpnet-vpn.state hooks for the Quickshell Control Center panel
        # (VpnState.qml, .copilot/plans/control-center.md §9.6/§10 I2) — see
        # corpnetVpnStateHook's own comment for why a fixed /run path rather
        # than a RuntimeDirectory.
        #
        # The leading "-" on every one of these is LOAD-BEARING, not
        # decorative: this is the user's actual work VPN, and a failure in
        # this bookkeeping script (e.g. /run transiently unwritable) must
        # never make systemd consider corpnet-vpn(@).service itself failed
        # and tear the tunnel down over a side effect that exists only for
        # the panel.
        ExecStartPre = "-${corpnetVpnStateHook} connecting ${region}";
        ExecStartPost = "-${corpnetVpnStateHook} connected ${region}";
        ExecStopPost = "-${corpnetVpnStateHook} disconnected";
        ExecStart = "${pkgs.gpclient}/bin/gpclient connect --as-gateway --browser ${corpnetBrowserBin} --os ${gpclientReportedOs} --script ${corpnetVpncScript}/bin/corpnet-vpnc-script ${gateway}";
      };
    };
in
{
  config = mkIf cfg.enable (mkMerge [
    {
      networking.networkmanager.dns = lib.mkDefault "systemd-resolved";
      services.resolved.enable = lib.mkDefault true;

      services.gnome.glib-networking.enable = true;
      security.polkit.enable = true;
      # Let the local user toggle the corpnet VPN units (start/stop/restart)
      # without a password prompt, so the waybar indicator and manual
      # `systemctl start corpnet-vpn@<region>` work friction-free. Scoped to
      # corpnet-vpn* units and this one user; every other unit still authenticates.
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.systemd1.manage-units" &&
              subject.user == ${builtins.toJSON vpnUser}) {
            var unit = action.lookup("unit");
            if (unit && /^corpnet-vpn(@[^.]*)?\.service$/.test(unit)) {
              return polkit.Result.YES;
            }
          }
        });
      '';
      security.rtkit.enable = true;

      environment.etc."NetworkManager/dispatcher.d/99-validate-dns" = {
        source = "${vpnDNSDispatcher}/bin/99-validate-dns";
        mode = "0755";
      };

      # Route the GlobalProtect SAML callback scheme to gpclient (see
      # gpCallbackHandler above) so external-browser auth can complete.
      xdg.mime.defaultApplications."x-scheme-handler/globalprotectcallback" =
        "globalprotect-callback.desktop";

      # nixpkgs ships gpclient/gpauth 2.5.1, which the Microsoft GlobalProtect
      # portal rejects at getconfig (HTTP 512 auth-failed) because it omits the
      # Client Security Compliance fields the official client sends. 2.6.3 adds
      # them, so build the CLI from the pinned globalprotect-openconnect source.
      # gpauth and gpclient share one workspace Cargo.lock, so a single vendored
      # dep set covers both. buildRustPackage derives cargoDeps from the call-site
      # cargoHash (not reachable via overrideAttrs), so override cargoDeps directly.
      nixpkgs.overlays = lib.mkAfter [
        (
          final: prev:
            let
              gpSrc = inputs.globalprotect-openconnect;
              gpVersion = "2.6.3";
              gpCargoDeps = final.rustPlatform.fetchCargoVendor {
                src = gpSrc;
                name = "globalprotect-openconnect-${gpVersion}-vendor";
                hash = "sha256-pqZ/q31H2KXJR6Tt/591Xz8h0FH+/GFV5hcOK/q9fao=";
              };
              bumpTo263 =
                drv:
                drv.overrideAttrs (_old: {
                  version = gpVersion;
                  src = gpSrc;
                  cargoDeps = gpCargoDeps;
                });
            in
            {
              gpauth = bumpTo263 prev.gpauth;
              gpclient = bumpTo263 prev.gpclient;
            }
        )
      ];

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
        gpCallbackHandler
        desktop-file-utils # update-desktop-database for the callback handler

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

      services.pcscd.enable = true;

      # Toggleable corpnet VPN. `systemctl start corpnet-vpn` connects to the
      # default gateway (opening your broker-enabled browser for SAML auth);
      # `systemctl stop corpnet-vpn` disconnects. gpclient must run as root to
      # create the tun device, then drops to the desktop user to launch the
      # browser. Under systemd there is no SUDO_UID/PKEXEC_UID for it to discover
      # that user, so we set DOAS_USER (which gpclient also honors); it
      # reconstructs the graphical session env (DBUS/Wayland) by scanning that
      # user's /proc entries. The browser is passed explicitly (see
      # corpnetBrowserBin) because that session env does not carry PATH, so
      # --default-browser auto-detection would fail under the unit. Stopping the
      # unit tears down the tunnel, so the corp routes added by the vpnc-script
      # vanish with it. This mirrors the msft-vpn-diagnostics connect invocation.
      #
      # The corpnet-vpn@ template selects a gateway by region at start time, e.g.
      # `systemctl start corpnet-vpn@dublin` connects to
      # dublin.${cfg.corpnet.gatewayDomain}. Use it to fail over when the default
      # gateway is degraded, without a rebuild. Only run one corpnet-vpn unit at a
      # time (stop the running one before starting another); they each create a
      # tun device and install the same routes.
      systemd.services.corpnet-vpn = mkCorpnetVpnService {
        gateway = cfg.corpnet.gateway;
        label = cfg.corpnet.gateway;
      };

      systemd.services."corpnet-vpn@" = mkCorpnetVpnService {
        gateway = "%i.${cfg.corpnet.gatewayDomain}";
        label = "%i.${cfg.corpnet.gatewayDomain}";
      };

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
        # The broker's interactive auth (acquireTokenInteractively) drives
        # FIDO/security-key and PIN prompts through the `pinentry` crate, which
        # execs a binary literally named `pinentry`. Without one in PATH, a
        # security key that requires a PIN (always_uv) silently fails: the PIN
        # prompt is skipped, the PIN channel is dropped, and the FIDO flow
        # aborts with CancelledByUser (surfaced to MSAL/WorkIQ as
        # unknown_broker_error). pinentry-gnome3 provides a `pinentry` symlink
        # and renders a graphical prompt in the user's session.
        path = [ pkgs.pinentry-gnome3 ];
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
