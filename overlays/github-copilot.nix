{ inputs, copilotVersion }: final: prev: {
  github-copilot = final.callPackage ../packages/github-copilot.nix {
    src = inputs.github-copilot-deb;
    version = copilotVersion;
  };
}
