{ pkgs-unstable, ... }:

{
  services.udev.packages = [ pkgs-unstable.swayosd ];

  environment.systemPackages = [
    pkgs-unstable.swayosd
  ];

  systemd.user.services.sway-osd = {
    description = "Sway OSD";
    wantedBy = [ "graphical-session.target" ];
    after = [
      "graphical-session.target"
      "xdg-desktop-autostart.target"
    ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs-unstable.swayosd}/bin/swayosd-server";
      Restart = "on-failure";
    };
  };

  systemd.services.swayosd-libinput-backend = {
    description = "SwayOSD LibInput backend for listening to certain keys like CapsLock, ScrollLock, VolumeUp, etc.";
    documentation = [ "https://github.com/ErikReider/SwayOSD" ];
    wantedBy = [ "graphical.target" ];
    partOf = [ "graphical.target" ];
    after = [ "graphical.target" ];

    serviceConfig = {
      Type = "dbus";
      BusName = "org.erikreider.swayosd";
      ExecStart = "${pkgs-unstable.swayosd}/bin/swayosd-libinput-backend";
      Restart = "on-failure";
    };
  };
}
