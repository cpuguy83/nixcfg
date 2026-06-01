{
  description = "Flake for my main system";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/f830e6112b4dbdb98cb7668cd291ea07ffc288e8";

    buildx = {
      url = "github:docker/buildx";
      flake = false;
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
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
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland = {
      url = "github:hyprwm/hyprland/v0.55.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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

    himmelblau = {
      url = "github:himmelblau-idm/himmelblau/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprtasking = {
      # TODO: return to raybbian/hyprtasking once Hyprland 0.55 support lands.
      url = "github:yerlotic/hyprtasking/3390ce22bdbf2c2f59dad495c218ca3f9e82572e";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.hyprland.follows = "hyprland";
    };

    waybar = {
      url = "github:Alexays/Waybar";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim/nixos-26.05";
    };

    nixd = {
      url = "github:nix-community/nixd";
      inputs.nixpkgs.follows = "nixpkgs";
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
      url = "github:cpuguy83/nix-handy-stt";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.handy.follows = "handy";
    };

    calbar = {
      url = "github:cpuguy83/calbar";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ghostty = {
      url = "github:ghostty-org/ghostty/v1.3.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vekil = {
      url = "github:sozercan/vekil";
      flake = false;
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
        overlays = [
          (import ./overlays/docker-buildx.nix { inherit inputs; })
          (import ./overlays/xdph.nix)
        ];
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
