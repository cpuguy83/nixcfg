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

  outputs = { nixpkgs, ... } @ inputs:
    let
      lanzaboote = inputs.lanzaboote;
      system = "x86_64-linux";
      pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${system};
    in {

    nixosConfigurations = {
      nixos = nixpkgs.lib.nixosSystem {
        inherit system;

        specialArgs = {
          inherit pkgs-unstable;
        };

        modules = [
          ./configuration.nix
          lanzaboote.nixosModules.lanzaboote

          ({pkgs, lib, ...}: {
            boot.loader.systemd-boot.enable = lib.mkForce false;
            boot.initrd.systemd.enable = true;
            boot.lanzaboote = {
              enable = true;
              pkiBundle = "/var/lib/sbctl";
            };
          })

          (import ./overlays)
        ];
      };
    };
  };
}
