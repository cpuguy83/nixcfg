{ lib, zen-browser, ... }:

{
  home-manager.users.cpuguy83 = lib.mkMerge [{
    imports = [
      zen-browser.homeModules.default
    ];
    programs.zen-browser.enable = true;
    programs.zen-browser.policies = {
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
        "{d634138d-c276-4fc8-924b-40a0ea21d284}" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/file/4529740/1password_x_password_manager-8.11.0.29.xpi";
        };
        "chrome-gnome-shell@gnome.org" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/file/4300298/gnome_shell_integration-12.xpi";
        };
        "gsconnect@andyholmes.github.io" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/file/3626312/gsconnect-8.xpi";
        };
        "linux-entra-sso@example.com" = {
          installation_mode = "force_installed";
          install_url = "https://github.com/siemens/linux-entra-sso/releases/download/v1.4.0/linux_entra_sso-1.4.0.xpi";
        };
        "sponsorBlocker@ajay.app" = {
          installation_mode = "force_installed";
          install_url= "https://addons.mozilla.org/firefox/downloads/file/4535341/sponsorblock-5.13.3.xpi";
        };
        "uBlock0@raymondhill.net" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/file/4531307/ublock_origin-1.65.0.xpi";
        };
      };
    };
  }];
}

