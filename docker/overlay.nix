(self: prev: {
  docker_28 = prev.docker_28.override {
    version = "28.4.0";
    cliRev = "v28.4.0";
    cliHash = "sha256-SgePAc+GvjZgymu7VA2whwIFEYAfMVUz9G0ppxeOi7M=";
    mobyRev = "v28.4.0";
    mobyHash = "sha256-hiuwdemnjhi/622xGcevG4rTC7C+DyUijE585a9APSM=";
    containerd = prev.containerd;
  };

  docker-buildx = prev.docker-buildx.overrideAttrs (_: rec {
    version = "0.28.0";
    rev = "1";
    src = prev.fetchFromGitHub {
        owner = "docker";
        repo = "buildx";
        rev = "v${version}";
        sha256 = "sha256-sYhmXVc1pU0nzG57AIuaLqUOWz9MfFlpJZQ9B5Ki5ik=";
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
