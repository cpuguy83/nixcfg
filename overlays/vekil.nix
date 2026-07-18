{ inputs }:
final: prev: {
  vekil = final.callPackage ../packages/vekil { src = inputs.vekil; };
}
