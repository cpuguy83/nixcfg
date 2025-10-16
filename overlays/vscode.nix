self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (builtins.fetchTarball {
      url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
      sha256 = "0i1vcm10mq9hb3whp580nbdcdbjag9ag8iawyk4xhyirn2s525h5";
    });
    version = "latest";
  });
}
