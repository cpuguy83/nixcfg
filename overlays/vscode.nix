self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (
      builtins.fetchTarball {
        url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
        sha256 = "1jbil7kx915r39zy0aixwa482hxrfhvhks2csidf0lk0bvn16l5g";
      }
    );
    version = "latest";
  });
}
