{ ... }:

{
  home-manager.users.cpuguy83.programs.waybar = {
    enable = false;
    systemd.enable = true;
    settings = [{
      layer = "top";
      position = "top";
      height = 25;
      modules-right = [
        "pulseaudio"
        "tray"
        "clock"
      ];
      tray = {
        spacing = 10;
      };
      pulseaudio = {
        format = "{volume}% {icon}  {format_source}";
        format-bluetooth = "{volume}% {icon} {format_source}";
        format-bluetooth-muted = " {icon} {format_source}";
        format-icons = {
          car = "";
          default = [ "" "" "" ];
          handsfree = "";
          headphones = "";
          headset = "";
          phone = "";
          portable = "";
        };
        format-muted = " {format_source}";
        format-source = "{volume}% ";
        format-source-muted = "";
        on-click  = "pavucontrol";
      };
    }];
  };
}
