self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (
      builtins.fetchTarball {
        url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
        sha256 = "0ylvhpk0pviz14ph937mxvw6mrdwqad87rdg272dgqs7cd28ck3w";
      }
    );
    version = "latest";
  });
}
