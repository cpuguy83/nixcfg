{
  description = "Flake for my main system";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      # Optional but recommended to limit the size of your system closure.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      # IMPORTANT: we're using "libgbm" and is only available in unstable so ensure
      # to have it up-to-date or simply don't specify the nixpkgs input
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "github:hyprwm/hyprland/v0.51.1";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
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
      url = "github:r00t3g/hyprtasking/9388b8ca1bd53a5bfa89b1a6caec7a801df0b6aa"; # fork with fixes for hyprland 0.51
      inputs.hyprland.follows = "hyprland";
    };

    waybar = {
      url = "github:Alexays/Waybar";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, hyprland, ... }@inputs:
  let
    system = "x86_64-linux";
    pkgs-unstable = import nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    nixosConfigurations = {
      yavin4 = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit pkgs-unstable inputs;
        };

        modules = [
          ({ ...}: {
            nix.settings.substituters = [
              "https://hyprland.cachix.org"
            ];

            nix.settings.trusted-substituters = [
              "https://hyprland.cachix.org"
            ];

            nix.settings.trusted-public-keys = [
              "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
            ];

            nixpkgs.config.allowUnfree = true;
          })
          ({
            nixpkgs.overlays = [
              inputs.waybar.overlays.default
              inputs.firefox-addons.overlays.default
            ];
            home-manager.useUserPackages = true;
            home-manager.useGlobalPkgs = true;
            home-manager.extraSpecialArgs = {
              inherit inputs;
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
