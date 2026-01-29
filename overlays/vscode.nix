self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (
      builtins.fetchTarball {
        url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
        sha256 = "17qa1zqam9fshyrf14853pmazv02yd5ip6qp4xph9sl24px1sdpy";
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
