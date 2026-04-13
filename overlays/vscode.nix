self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (
      builtins.fetchTarball {
        url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
        sha256 = "1a07s2k27y6wl6dbinwar05605300f5l16g13b068hjs1flx17za";
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
