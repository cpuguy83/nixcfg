{ pkgs, ... }:

let
  backend = pkgs.callPackage ../../../packages/qs-launcher { };
  launcher = pkgs.writeShellScriptBin "qs-launcher" ''
    export QS_LAUNCHER_QALC=${pkgs.libqalculate}/bin/qalc
    export QS_LAUNCHER_UWSM=${pkgs.uwsm}/bin/uwsm
    export QS_LAUNCHER_COPY=${pkgs.wl-clipboard}/bin/wl-copy

    exec ${backend}/bin/qs-launcher "$@"
  '';
in
{
  home.packages = [ launcher ];

  systemd.user.services.quickshell-bar = {
    Unit = {
      Wants = [ "qs-launcher-state.service" ];
      After = [ "qs-launcher-state.service" ];
    };
    Service = {
      RuntimeDirectory = "qs-launcher-daemon";
      RuntimeDirectoryMode = "0700";
      RuntimeDirectoryPreserve = "no";
    };
  };

  systemd.user.services.qs-launcher-state = {
    Unit = {
      Description = "Session-only Quickshell launcher query memory";
      Before = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/true";
      RemainAfterExit = true;
      RuntimeDirectory = "qs-launcher";
      RuntimeDirectoryMode = "0700";
      RuntimeDirectoryPreserve = "no";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.configFile."xdg-terminals.list".text = ''
    com.mitchellh.ghostty.desktop
  '';
}
