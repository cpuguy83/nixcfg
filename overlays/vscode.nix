self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (builtins.fetchTarball {
      url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
      sha256 = "1gp6rjhxvp9jamb0pz9bdfqd3bn1jqhb587v1jjn1hkyn2nzdypi";
    });
    version = "latest";
  });
}
