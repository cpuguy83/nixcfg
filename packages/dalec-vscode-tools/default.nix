# DALEC VSCode Tools: language support for Dalec spec files. Not yet in
# nixpkgs' vscode-extensions set, so packaged straight from the marketplace
# following the buildVscodeMarketplaceExtension convention used upstream.
{ lib
, vscode-utils
,
}:

vscode-utils.buildVscodeMarketplaceExtension {
  mktplcRef = {
    publisher = "ms-kubernetes-tools";
    name = "dalec-vscode-tools";
    version = "0.0.5";
    hash = "sha256-u8n1f1ZrBUdLLDynfVTDwLr+DT9S70mXtMzjbly7JgE=";
  };

  meta = {
    description = "Dalec VSCode extension for developers";
    downloadPage = "https://marketplace.visualstudio.com/items?itemName=ms-kubernetes-tools.dalec-vscode-tools";
    homepage = "https://github.com/project-dalec/dalec-vscode-extension";
    license = lib.licenses.asl20;
  };
}
