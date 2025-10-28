self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (
      builtins.fetchTarball {
        url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
        sha256 = "0790pc2z7ja4b5xwrmwcs08amspkbqaqjlvzxnmsygma9rqbqmsf";
      }
    );
    version = "latest";
  });
}
