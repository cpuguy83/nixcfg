(final: prev: {
  moby = prev.docker.moby.overrideAttrs (_: rec {
      version = "28.3.0";
      commit = "265f709647947fb5a1adf7e4f96f2113dcc377bd";
      src = prev.fetchFromGitHub {
        owner = "moby";
        repo = "moby";
        rev = "v${version}";
        sha256 = "sha256-uAYObHkORcGX1vokqj+b3BgQTSYJ0TvFoXpooURxR0s=";
      };

    buildPhase = ''
      export GOCACHE="$TMPDIR/go-cache"
      # build engine
      export AUTO_GOPATH=1
      export DOCKER_GITCOMMIT="${commit}"
      export VERSION="${version}"
      ./hack/make.sh dynbinary
    '';
  });

  docker = prev.docker.overrideAttrs (_: rec {
    version = "28.3.0";
    commit = "38b7060a218775811da953650d8df7d492653f8f";
     src = prev.fetchFromGitHub {
       owner = "docker";
       repo = "cli";
       rev = "v${version}"; 
       sha256 = "sha256-flPE/XQ6R0o3p6LOXBG/IJtZom29nYwm7Q+VJbIwI0A=";
     };

    buildPhase = ''
      export GOCACHE="$TMPDIR/go-cache"

      # Mimic AUTO_GOPATH
      mkdir -p .gopath/src/github.com/docker/
      ln -sf $PWD .gopath/src/github.com/docker/cli
      export GOPATH="$PWD/.gopath:$GOPATH"
      export GITCOMMIT="${commit}"
      export VERSION="${version}"
      export BUILDTIME="1970-01-01T00:00:00Z"
      make dynbinary
    '';

    passthru = ({}) // {
      moby = final.moby;
    };
  });

  docker-buildx = prev.docker-buildx.overrideAttrs (_: rec {
    version = "0.25.0";
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
