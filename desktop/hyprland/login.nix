{ pkgs, ... }:
let
  tuigreet = pkgs.greetd.tuigreet;
in
{
  services.greetd = {
    enable = true;
    restart = true;
    settings = {
      default_session = {
        command = "${tuigreet}/bin/tuigreet --time --cmd 'uwsm start hyprland-uwsm.desktop'";
        user = "cpuguy83";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    greetd.tuigreet
  ];

  security.pam.services.greetd.enableGnomeKeyring = true;

  systemd.services.greetd.serviceConfig = {
    Type = "idle";
    StandardInput = "tty";
    StandardOutput = "tty";
    StandardError = "journal"; # Without this errors will spam on screen
    # Without these bootlogs will spam on screen
    TTYReset = true;
    TTYVHangup = true;
    TTYVTDisallocate = true;
  };
}
