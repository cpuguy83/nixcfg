{ pkgs-unstable, pkgs, ... }:

{
  environment.systemPackages = [
    pkgs-unstable.ashell
    pkgs.networkmanagerapplet
  ];

  systemd.user.services.nm-applet = {
    enable = true;
    description = "NetworkManager Applet";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet";
      Restart = "on-failure";
    };
  };

  home-manager.users.cpuguy83.home.file.".config/caelestia/shell.json".text = ''
    {
        "background": {
            "enabled": true
        },
        "bar": {
            "dragThreshold": 20,
            "externalAudioProgram": ["pavucontrol"],
            "persistent": true,
            "showOnHover": true,
            "status": {
                "showAudio": false,
                "showBattery": false,
                "showBluetooth": true,
                "showKbLayout": false,
                "showNetwork": true
            },
            "workspaces": {
                "activeIndicator": true,
                "activeLabel": "󰮯 ",
                "activeTrail": false,
                "label": "  ",
                "occupiedBg": false,
                "occupiedLabel": "󰮯 ",
                "rounded": true,
                "showWindows": true,
                "shown": 5
            }
        },
        "border": {
            "rounding": 25,
            "thickness": 10
        },
        "dashboard": {
            "mediaUpdateInterval": 500,
            "visualiserBars": 45
        },
        "launcher": {
            "actionPrefix": ">",
            "dragThreshold": 50,
            "vimKeybinds": false,
            "enableDangerousActions": false,
            "maxShown": 8,
            "maxWallpapers": 9,
            "useFuzzy": {
                "apps": false,
                "actions": false,
                "schemes": false,
                "variants": false,
                "wallpapers": false
            }
        },
        "lock": {
            "maxNotifs": 5
        },
        "notifs": {
            "actionOnClick": false,
            "clearThreshold": 0.3,
            "defaultExpireTimeout": 5000,
            "expandThreshold": 20,
            "expire": false
        },
        "osd": {
            "hideDelay": 2000
        },
        "paths": {
            "mediaGif": "root:/assets/bongocat.gif",
            "sessionGif": "root:/assets/kurukuru.gif",
            "wallpaperDir": "~/Pictures/Wallpapers"
        },
        "services": {
          "weatherLocation": "10,10",
          "useFahrenheit": false,
          "useTwelveHourClock": false
        },
        "session": {
            "dragThreshold": 30,
            "vimKeybinds": false,
            "commands": {
                "logout": ["loginctl", "terminate-user", ""],
                "shutdown": ["systemctl", "poweroff"],
                "hibernate": ["systemctl", "hibernate"],
                "reboot": ["systemctl", "reboot"]
            }
        }
    }
  '';

  home-manager.users.cpuguy83.home.file.".config/ashell/config.toml".text = ''
    clipboard_cmd = "cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"
    [modules]
    left = [ "Workspaces", "WindowTitle" ]
    center = [ "MediaPlayer" ]
    right = [ "Clipboard", "Tray", [ "Clock", "Settings" ], "Notifications" ]

    [settings]
    bluetooth_more_cmd = "blueman-manager"
    remove_airplane_btn = true
    audio_sinks_more_cmd = "pavucontrol -t 3"
    audio_sources_more_cmd = "pavucontrol -t 4"
    vpn_more_cmd = "nm-connection-editor"

    [appearance]
    style = "Solid"
    opacity = 0.6

    [[CustomModule]]
    # The name will link the module in your left/center/right definition
    name = "Notifications"
    # The default icon for this custom module
    icon = ""
    # The command that will be executed on click
    command = "swaync-client -t -sw"
    # You can optionally configure your custom module to update the UI using another command
    # The output right now follows the waybar json-style output, using the `alt` and `text` field
    # E.g. `{"text": "3", "alt": "notification"}`
    listen_cmd = "swaync-client -swb"
    # You can define behavior for the `text` and `alt` fields
    # Any number of regex can be used to change the icon based on the alt field
    icons.'dnd.*' = ""
    # Another regex can optionally show a red "alert" dot on the icon
    alert = ".*notification"
  '';
}
