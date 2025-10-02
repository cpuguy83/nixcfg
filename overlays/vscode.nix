self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (builtins.fetchTarball {
      url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
      sha256 = "07mn0l28bk9vkhjbnylz99rf9sl2ydj43ldrfvywbbi7g5if4z3c";
    });
    version = "latest";
  });
}
