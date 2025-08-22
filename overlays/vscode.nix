{ pkgs }:
self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (builtins.fetchTarball {
      url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
      sha256 = "0cfdzn0jndwdb7c70kasyr09hjp7q8nwd5pas23cyq13p05q0nlk";
    });
    version = "latest";
    buildInputs = super.buildInputs ++ [ pkgs.krb5 ];
  });
}
