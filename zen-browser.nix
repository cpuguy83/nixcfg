{ pkgs, pkgs-unstable, inputs, ... }:

let
  addons = pkgs.firefox-addons;
  onepassword = addons."1password-x-password-manager";
in {
  environment.systemPackages = [
    pkgs-unstable.firefoxpwa
  ];

  environment.sessionVariables.MOZ_ENBALE_WAYLAND = "1";

  home-manager.users.cpuguy83 = {
    imports = [
      inputs.zen-browser.homeModules.default
    ];

    programs.zen-browser = {
      enable = true;

      profiles = {
        default = {
          extensions.packages = with addons; [
            ublock-origin
            sponsorblock
            gsconnect
            pwas-for-firefox
            onepassword
          ];
        };
      };


      nativeMessagingHosts = [pkgs-unstable.firefoxpwa];
      policies = {
        AutofillAddressEnabled = true;
        AutofillCreditCardEnabled = false;
        DisableAppUpdate = true;
        DisableFeedbackCommands = true;
        DisableFirefoxStudies = true;
        DisablePocket = true;
        DisableTelemetry = true;
        DontCheckDefaultBrowser = true;
        NoDefaultBookmarks = true;
        OfferToSaveLogins = false;
        EnableTrackingProtection = {
          Value = true;
          Locked = true;
          Cryptomining = true;
          Fingerprinting = true;
        };

        ExtensionSettings = {
          "linux-entra-sso@example.com" = {
            installation_mode = "force_installed";
            install_url = "https://github.com/siemens/linux-entra-sso/releases/download/v1.4.0/linux_entra_sso-1.4.0.xpi";
          };
        };
      };
    };
  };
}

