{ inputs }:
final: prev: {
  vekil = final.callPackage ../packages/vekil.nix { src = inputs.vekil; };
}
