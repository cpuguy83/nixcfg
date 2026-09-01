{ inputs }:
final: prev: {
  tether = final.callPackage ../packages/tether { src = inputs.tether; };
}
