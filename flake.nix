{
  description = "Flake for my main system";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    buildx = {
      url = "github:docker/buildx?ref=refs/tags/v0.35.0";
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
      url = "github:hyprwm/hyprland/v0.55.4";
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

    # Pin gpclient/gpauth to 2.6.3; nixpkgs is stuck at 2.5.1, which the Microsoft
    # GlobalProtect portal rejects at getconfig (HTTP 512 auth-failed) because it
    # omits the Client Security Compliance fields the official client sends. 2.6.3
    # adds them. Consumed as a plain source tree (built via an overlay in
    # modules/nixos/msft-corp); submodules carry the vendored openconnect/libxml2
    # that gpclient compiles.
    globalprotect-openconnect = {
      url = "git+https://github.com/yuezk/GlobalProtect-openconnect?ref=refs/tags/v2.6.3&submodules=1";
      flake = false;
    };

    hyprtasking = {
      # TODO: return to raybbian/hyprtasking once Hyprland 0.55 support lands.
      url = "github:raybbian/hyprtasking";
      inputs.nixpkgs.follows = "nixpkgs";
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
      inputs.nixpkgs.follows = "nixpkgs";
    };

    handy-mine = {
      url = "github:cpuguy83/nix-handy-stt";
      inputs.nixpkgs.follows = "nixpkgs";
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

    github-copilot-deb = {
      url = "file+https://github.com/github/app/releases/download/v1.0.21/GitHub-Copilot-linux-x64.deb";
      flake = false;
    };

    vscode-insiders = {
      url = "tarball+https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
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

      # Recover the GitHub Copilot version from the locked deb URL so the only
      # thing update.sh has to bump is the tag in the github-copilot-deb input.
      # ./flake.lock is a guaranteed sibling of flake.nix, so this read is stable
      # regardless of where the package/overlay files live.
      copilotVersion = builtins.head (
        builtins.match ".*/v([0-9.]+)/.*" (builtins.fromJSON (builtins.readFile ./flake.lock))
        .nodes.github-copilot-deb.locked.url
      );

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
            inherit inputs pkgs-unstable copilotVersion;
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
            inherit pkgs-unstable inputs copilotVersion;
          };

          modules = [
            {
              home-manager.useUserPackages = true;
              home-manager.useGlobalPkgs = true;
              home-manager.extraSpecialArgs = {
                inherit inputs;
                inherit pkgs-unstable;
                inherit copilotVersion;
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
