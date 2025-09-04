self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (builtins.fetchTarball {
      url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
      sha256 = "1rqc5w0xss4kmf7viiqg3yskv4450an0divmw5mvifzqsvnik6js";
    });
    version = "latest";
  });
}
