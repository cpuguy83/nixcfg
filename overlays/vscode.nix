self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (
      builtins.fetchTarball {
        url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
        sha256 = "1wbxkv4z0h4v5ylrnw32rdrx1naja9jxsp7b5qsffvk6fypv70c9";
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
