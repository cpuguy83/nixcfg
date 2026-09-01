{ config
, lib
, ...
}:

let
  cfg = config.mine.tether;
  btPkg = config.hardware.bluetooth.package;
in
{
  options.mine.tether = {
    enable = lib.mkEnableOption "system-level support for the tether daemon";

    bluetoothAccessory = {
      enable = lib.mkEnableOption ''
        presenting this machine to iOS as an A/V Hands-Free Bluetooth accessory.

        iOS only offers "Show Message Notifications" and "Sync Contacts" to a
        device whose Class of Device is major 4 / minor 8, so tether's
        SMS/iMessage mirroring is unreachable without this. It changes how the
        machine appears over Bluetooth to everything, not just the iPhone,
        which is why upstream ships this unit but never enables it by default
      '';

      adapter = lib.mkOption {
        type = lib.types.str;
        default = "hci0";
        description = "Bluetooth adapter whose Class of Device is set.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # tetherd listens on 5134; the iPhone app finds it over mDNS and dials in.
      networking.firewall.allowedTCPPorts = [ 5134 ];

      # avahi-daemon otherwise runs with disable-publishing=yes /
      # disable-user-service-publishing=yes and refuses EntryGroupNew from
      # D-Bus clients with NOT_PERMITTED, so _tether._tcp is never advertised
      # and the iPhone can't discover the daemon at all.
      services.avahi.publish.enable = true;
      services.avahi.publish.userServices = true;
    })

    (lib.mkIf (cfg.enable && cfg.bluetoothAccessory.enable) {
      assertions = [
        {
          assertion = config.hardware.bluetooth.enable;
          message = "mine.tether.bluetoothAccessory requires hardware.bluetooth.enable";
        }
      ];

      # Equivalent to upstream's packaging/systemd/tether-btclass@.service,
      # written out directly here (absolute btmgmt path, single known adapter)
      # rather than instantiating their template, since bluetoothd rewrites
      # the Class of Device on every start and this is the only thing that
      # re-applies it. PartOf reruns this on every bluetooth.service restart.
      systemd.services.tether-btclass = {
        description = "Set Bluetooth Class of Device to A/V Hands-Free for tether";
        documentation = [ "https://github.com/zackb/tether/blob/main/docs/BLUETOOTH.md" ];
        after = [ "bluetooth.service" ];
        partOf = [ "bluetooth.service" ];
        wantedBy = [ "bluetooth.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          for _ in $(seq 1 10); do
            ${btPkg}/bin/btmgmt --index ${cfg.bluetoothAccessory.adapter} class 4 8 >/dev/null 2>&1 || true
            if ${btPkg}/bin/btmgmt --index ${cfg.bluetoothAccessory.adapter} info 2>/dev/null \
                 | grep -q 'class 0x..0408'; then
              exit 0
            fi
            sleep 1
          done
          exit 1
        '';
      };

      # tether reads /proc/<bluetoothd>/cmdline for -E / --experimental; the
      # Experimental=true already in main.conf enables the D-Bus interfaces
      # but is invisible to that check, so without this tether falls back to
      # compatibility mode (MAP+PBAP only, no ANCS notification mirroring).
      # Confirm the flag list here still matches `systemctl cat bluetooth.service`
      # at implementation time -- nixpkgs' own ExecStart construction is the
      # source of truth, this just appends --experimental to it.
      systemd.services.bluetooth.serviceConfig.ExecStart = lib.mkForce [
        ""
        (lib.concatStringsSep " " (
          [
            "${btPkg}/libexec/bluetooth/bluetoothd"
            "-f"
            "/etc/bluetooth/main.conf"
          ]
          ++ lib.optional (config.hardware.bluetooth.disabledPlugins != [ ])
            "--noplugin=${lib.concatStringsSep "," config.hardware.bluetooth.disabledPlugins}"
          ++ [ "--experimental" ]
        ))
      ];
    })
  ];
}
