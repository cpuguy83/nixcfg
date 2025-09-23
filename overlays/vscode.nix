self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (builtins.fetchTarball {
      url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
      sha256 = "1ly8bki4rr7g0xfi0nsj1y3l8v3hkzxg94gp84djmx9rdrbdpf5w";
    });
    version = "latest";
  });
}
