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
  };

  outputs = { nixpkgs, nixpkgs-unstable, ... } @ inputs:
    let
      lanzaboote = inputs.lanzaboote;
      system = "x86_64-linux";
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      pkgs-unstable.config.allowUnfree = true;

      nixosConfigurations = {
        nixos = nixpkgs.lib.nixosSystem {
        inherit system;

        specialArgs = {
          pkgs-unstable = pkgs-unstable;
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

          ({
            desktop.de = "gnome";
            msft-corp.enable = false;
          })
        ];
      };
    };
  };
}
