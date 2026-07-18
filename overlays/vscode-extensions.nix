final: prev: {
  vscode-extensions = prev.vscode-extensions // {
    ms-kubernetes-tools = prev.vscode-extensions.ms-kubernetes-tools // {
      dalec-vscode-tools = final.callPackage ../packages/dalec-vscode-tools { };
    };
  };
}
