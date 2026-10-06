{ pkgs }:

let
  addons = pkgs.firefox-addons;
  onepassword = addons."1password-x-password-manager";
in
{
  profiles = {
    default = {
      extensions.packages = with addons; [
        ublock-origin
        sponsorblock
        gsconnect
        onepassword
      ];

      settings = {
        # Automatically load client certificates from OS PKCS#11 modules
        # (discovered via p11-kit) for smart card / YubiKey PIV auth.
        "security.osclientcerts.autoload" = true;
        "widget.non-native-theme.scrollbar.size.override" = 15;
      };

      search.force = true;
      search.engines = {
        nix-packages = {
          name = "Nix Packages";
          urls = [
            {
              template = "https://search.nixos.org/packages";
              params = [
                {
                  name = "channel";
                  value = "unstable";
                }
                {
                  name = "query";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
          icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          definedAliases = [ "@np" ];
        };

        nix-options = {
          name = "Nix Options";
          urls = [
            {
              template = "https://search.nixos.org/options";
              params = [
                {
                  name = "channel";
                  value = "unstable";
                }
                {
                  name = "query";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
          icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          definedAliases = [ "@no" ];
        };

        nixos-wiki = {
          name = "NixOS Wiki";
          urls = [
            {
              template = "https://wiki.nixos.org/w/index.php";
              params = [
                {
                  name = "search";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
          icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          definedAliases = [ "@nw" ];
        };
      };
    };
  };

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

    SecurityDevices = {
      Add = {
        "OpenSC PKCS#11" = "${pkgs.opensc}/lib/opensc-pkcs11.so";
      };
    };

    ExtensionSettings = {
      "better-ghsa@sbk.wtf" = {
        installation_mode = "force_installed";
        install_url = "https://addons.mozilla.org/firefox/downloads/file/5073321/better_ghsa-0.0.9.xpi";
      };
      # Dumpster Fire
      # "{995A6AA5-D7FF-4B54-BD04-71C6999BB915}" = {
      #   installation_mode = "force_installed";
      #   install_url = "https://addons.mozilla.org/firefox/downloads/file/5033206/dumpster_fire-1.0.4.xpi";
      # };
      "linux-entra-sso@example.com" = {
        installation_mode = "force_installed";
        install_url = "https://github.com/siemens/linux-entra-sso/releases/download/v1.12.0/linux_entra_sso-1.12.0.xpi";
      };
    };
  };
}
