(self: prev: {
  docker_28 = prev.docker_28.override {
    version = "28.3.3";
    cliRev = "v28.3.3";
    cliHash = "sha256-LsV9roOPw0LccvBUeF3bY014OwG6QpnVsLf+dqKyvsg=";
    mobyRev = "v28.3.3";
    mobyHash = "sha256-YfdnCAc9NgLTuvxLHGhTPdWqXz9VSVsQsfzLD3YER3g=";
    containerd = prev.containerd;
  };

  docker-buildx = prev.docker-buildx.overrideAttrs (_: rec {
    version = "0.27.0";
    rev = "1";
    src = prev.fetchFromGitHub {
        owner = "docker";
        repo = "buildx";
        rev = "v${version}";
        sha256 = "sha256-DdG2z0raDHcbBMDl7C0WORKhG0ZB9Gvie8u4/isE8ow=";
      };
      ldflags = [
        "-w"
        "-s"
        "-X github.com/docker/buildx/version.Package=github.com/docker/buildx"
        "-X github.com/docker/buildx/version.Version=${version}"
        "-X github.com/docker/buildx/version.Revision=${rev}"
      ];
  });
})
