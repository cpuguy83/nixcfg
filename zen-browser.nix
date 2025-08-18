{ pkgs, pkgs-unstable, inputs, ... }:

{
  environment.systemPackages = [
    pkgs-unstable.firefoxpwa
  ];

  home-manager.users.cpuguy83 = {
    imports = [
      inputs.zen-browser.homeModules.default
    ];

    programs.zen-browser = {
      enable = true;
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

        extensions = with inputs.firefox-addons.packages."${pkgs.system}"; [
          ublock-origin
          sponsorblock
          gsconnect
          pwas-for-firefox
          "1password-x-password-manager"
        ];
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

