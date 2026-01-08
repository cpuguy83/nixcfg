self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (
      builtins.fetchTarball {
        url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
        sha256 = "1jwsrgsc1ywwbcv8gh77ak4b1qspkm13n2f7bj669f49c1j99iwd";
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
