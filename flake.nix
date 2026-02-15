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

    hyprland.url = "github:hyprwm/hyprland/v0.53.3";
    # hyprland-plugins = {
    #   url = "github:hyprwm/hyprland-plugins/v0.53.0";
    #   inputs.hyprland.follows = "hyprland";
    # };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    azurevpnclient = {
      url = "github:cpuguy83/nix-azurevpn-client";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprtasking = {
      url = "github:raybbian/hyprtasking";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.hyprland.follows = "hyprland";
    };

    waybar = {
      url = "github:Alexays/Waybar/a9ef11a2b387593a50dde6ff1ce22f434a840bd8";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
    };

    nixd = {
      url = "github:nix-community/nixd";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    opencode = {
      url = "github:anomalyco/opencode";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    handy = {
      url = "github:cjpais/handy";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    handy-mine = {
      url = "github:cpuguy83/nix-handy-tts";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.rust-overlay.follows = "rust-overlay";
    };

    calbar = {
      url = "github:cpuguy83/calbar";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
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
        "cpuguy83@yavin4" = inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = {
            inherit inputs pkgs-unstable;
          };
          modules = [
            {
              home.username = "cpuguy83";
              home.homeDirectory = "/home/cpuguy83";
              nixpkgs.config.allowUnfree = true;
            }
            ./home.nix
            ./hosts/yavin4/home.nix
            ./overlays
          ];
        };
      };

      packages.${system} = {
        "home-cpuguy83@yavin4" = self.homeConfigurations."cpuguy83@yavin4".activationPackage;
      };

      nixosConfigurations = {
        yavin4 = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit pkgs-unstable inputs;
          };

          modules = [
            {
              home-manager.useUserPackages = true;
              home-manager.useGlobalPkgs = true;
              home-manager.extraSpecialArgs = {
                inherit inputs;
                inherit pkgs-unstable;
              };

              home-manager.users.cpuguy83 = {
                imports = [
                  ./home.nix
                  ./hosts/yavin4/home.nix
                ];
              };
            }

            ./configuration.nix
            ./hosts/yavin4/system.nix
          ];
        };
      };
    };
}
