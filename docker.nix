{ pkgs, ... }:

{
  virtualisation.docker = {
    package = pkgs.docker_28; # explicitly use the overridden version
    enable = true;
    daemon.settings = {
      experimental = true;
      features.containerd-snapshotter = true;
    };
  };
}
