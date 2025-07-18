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
  };

  outputs = { nixpkgs, nixpkgs-unstable, ... } @ inputs:
    let
      zen-browser = inputs.zen-browser;
      lanzaboote = inputs.lanzaboote;
      system = "x86_64-linux";
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      home-manager = inputs.home-manager;
    in {
      pkgs-unstable.config.allowUnfree = true;

      nixosConfigurations = {
        nixos = nixpkgs.lib.nixosSystem {
        inherit system;

        specialArgs = {
          pkgs-unstable = pkgs-unstable;
          zen-browser = zen-browser;
        };

        modules = [
          (import ./overlays)

          ./docker.nix
          ./msft-vm
          ./msft-corp

          ./configuration.nix
          ./desktop
          ./1password.nix

          lanzaboote.nixosModules.lanzaboote
          ./boot.nix

          (import "${home-manager}/nixos")

          ./zen-browser.nix
          ({
            home-manager.useUserPackages = true;
            home-manager.useGlobalPkgs = true;
            desktop.de = "gnome";
            msft-corp.enable = false;
          })
        ];
      };
    };
  };
}
