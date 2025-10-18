{
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}:

let
  addons = pkgs.firefox-addons;
  onepassword = addons."1password-x-password-manager";
in
{
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

      nativeMessagingHosts = [ pkgs-unstable.firefoxpwa ];
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
            install_url = "https://github.com/siemens/linux-entra-sso/releases/download/v1.5.1/linux_entra_sso-1.5.1.xpi";
          };
        };
      };
    };
  };
}
