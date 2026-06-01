self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (
      builtins.fetchTarball {
        url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
        sha256 = "1zzhzqs5qvr78h906s5vvbimv7j4findav5fad7fiinxix4xp5rg";
      }
    );
    version = "latest";
    postPatch = builtins.replaceStrings
      [
        ''
          rm resources/app/node_modules/@vscode/ripgrep/bin/rg
          ln -s ${self.ripgrep}/bin/rg resources/app/node_modules/@vscode/ripgrep/bin/rg
        ''
      ]
      [
        ''
          rgPath="resources/app/node_modules/@vscode/ripgrep/bin/rg"
          if [ ! -e "$rgPath" ]; then
            rgPath="resources/app/node_modules/@vscode/ripgrep-universal/bin/linux-x64/rg"
          fi
          rm "$rgPath"
          ln -s ${self.ripgrep}/bin/rg "$rgPath"
        ''
      ]
      (old.postPatch or "");
    buildInputs =
      (old.buildInputs or [ ])
      ++ [
        self.webkitgtk_4_1
        self.libsoup_3
        self.musl
      ];
  });
}
