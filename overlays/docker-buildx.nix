{ inputs }:
final: prev:
let
  lock = builtins.fromJSON (builtins.readFile ../flake.lock);
  buildxRef = lock.nodes.buildx.locked.ref or (lock.nodes.buildx.original.ref or null);
  buildxTag =
    if buildxRef == null then
      null
    else
      let
        match = builtins.match "(refs/tags/)?(v.+)" buildxRef;
      in
      if match == null then null else builtins.elemAt match 1;
  version =
    if buildxTag == null then
      "unstable-${inputs.buildx.shortRev or (builtins.substring 0 7 inputs.buildx.rev)}"
    else
      let
        match = builtins.match "v(.+)" buildxTag;
      in
      if match == null then buildxTag else builtins.elemAt match 0;
  buildxVersion = if buildxTag == null then version else buildxTag;
in
{
  docker-buildx = prev.docker-buildx.overrideAttrs (_old: {
    inherit version;
    src = inputs.buildx;

    ldflags = [
      "-w"
      "-s"
      "-X github.com/docker/buildx/version.Package=github.com/docker/buildx"
      "-X github.com/docker/buildx/version.Version=${buildxVersion}"
    ] ++ final.lib.optionals (inputs.buildx ? rev) [
      "-X github.com/docker/buildx/version.Revision=${inputs.buildx.rev}"
    ];
  });
}
