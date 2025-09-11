self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (builtins.fetchTarball {
      url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
      sha256 = "1kj2xnwrx5qyadinh3d504n5h54zzll80hars79dq6hx2j2av5j0";
    });
    version = "latest";
  });
}
