self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (
      builtins.fetchTarball {
        url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
        sha256 = "0ajy3zqrc8fcixk5zk7xc4w066dqxz36fhrdkdpr80h05zqb4cpj";
      }
    );
    version = "latest";
    buildInputs =
      (old.buildInputs or [])
      ++ [
        self.webkitgtk_4_1
        self.libsoup_3
      ];
  });
}
