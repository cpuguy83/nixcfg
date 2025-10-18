(self: prev: {
  docker_28 = prev.docker_28.override {
    version = "28.5.1";
    cliRev = "v28.5.1";
    cliHash = "sha256-iT5FLzX8Pg07V0Uo+07gy3ChP/WgLTPs/vtxnFVmCG8=";
    mobyRev = "v28.5.1";
    mobyHash = "sha256-IlkEK4UeQjZsojbahzLy/rP3WqJUWXG9nthmBSEj10M=";
    containerd = prev.containerd;
  };

  docker-buildx = prev.docker-buildx.overrideAttrs (_: rec {
    version = "0.29.1";
    rev = "1";
    src = prev.fetchFromGitHub {
      owner = "docker";
      repo = "buildx";
      rev = "v${version}";
      sha256 = "sha256-H7U44g4rw15c3Snx88YgAanSw4dWanmTugpGBIwfI6A=";
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
