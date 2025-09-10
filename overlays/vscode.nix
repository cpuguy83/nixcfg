self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (builtins.fetchTarball {
      url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
      sha256 = "1317h66y5syw2bjsvmb7gcalikp0va88c65zarl419vbzi3vfy2i";
    });
    version = "latest";
  });
}
