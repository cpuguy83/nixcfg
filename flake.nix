{
  description = "Flake for my main system";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.3";
      # Optional but recommended to limit the size of your system closure.
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      # IMPORTANT: we're using "libgbm" and is only available in unstable so ensure
      # to have it up-to-date or simply don't specify the nixpkgs input
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "github:hyprwm/hyprland/v0.52.2";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins/v0.52.0";
      inputs.hyprland.follows = "hyprland";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    azurevpnclient = {
      url = "github:cpuguy83/nix-azurevpn-client";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprtasking = {
      # url = "github:raybbian/hyprtasking";
      url = "github:r00t3g/hyprtasking/9611bbd0db23bba9508da44f65989a7dc664d0a9"; # fork with fixes for hyprland 0.51
      inputs.hyprland.follows = "hyprland";
    };

    waybar = {
      url = "github:Alexays/Waybar";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
    };

    nixd = {
      url = "github:nix-community/nixd";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      homeConfigurations = {
        cpuguy83 = inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = {
            inherit inputs pkgs-unstable;
          };
          modules = [
            {
              home.username = "cpuguy83";
              home.homeDirectory = "/home/cpuguy83";
              nixpkgs.config.allowUnfree = true;

              nixpkgs.overlays = [
                inputs.rust-overlay.overlays.default
                inputs.waybar.overlays.default
                inputs.firefox-addons.overlays.default
                inputs.nixd.overlays.default
              ];
            }
            ./home.nix
            ./overlays
          ];
        };
      };

      packages.${system} = {
        home-cpuguy83 = self.homeConfigurations.cpuguy83.activationPackage;
      };

      nixosConfigurations = {
        yavin4 = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit pkgs-unstable inputs;
          };

          modules = [
            (
              { ... }:
              {
                nixpkgs.config.allowUnfree = true;

                nix.settings.substituters = [
                  "https://hyprland.cachix.org"
                ];

                nix.settings.trusted-substituters = [
                  "https://hyprland.cachix.org"
                ];

                nix.settings.trusted-public-keys = [
                  "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
                ];
              }
            )
            ({

              nixpkgs.overlays = [
                inputs.waybar.overlays.default
                inputs.firefox-addons.overlays.default
                inputs.nixd.overlays.default
              ];

              home-manager.useUserPackages = true;
              home-manager.useGlobalPkgs = true;
              home-manager.extraSpecialArgs = {
                inherit inputs;
                inherit pkgs-unstable;
              };

              home-manager.users.cpuguy83 = {
                imports = [
                  ./home.nix
                ];
              };
            })

            inputs.azurevpnclient.nixosModules.azurevpnclient
            ./modules.nix
            ./configuration.nix
            inputs.lanzaboote.nixosModules.lanzaboote
          ];
        };
      };
    };
}
