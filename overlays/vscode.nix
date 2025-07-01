self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (builtins.fetchTarball {
      url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
      sha256 = "0kb6rk6l2617ivw1ylnrq6srf6amnmss049lxc2l8j4nvb3mp5wf";
    });
    version = "latest";
  });
}
