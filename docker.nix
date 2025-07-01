{ pkgs, lib, ... }:

{
  virtualisation.docker = {
    enable = true;
    package = pkgs.docker; # explicitly use the overridden version
    daemon.settings = {
      experimental = true;
      features.containerd-snapshotter = true;
    };
  };

  systemd.services.docker.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${pkgs.docker.passthru.moby}/bin/dockerd --config-file=${pkgs.writeText "daemon.json" (builtins.toJSON {
      experimental = true;
      features = {
        "containerd-snapshotter" = true;
      };
    })}"
  ];
}
