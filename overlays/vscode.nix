self: super: {
  vscodeInsidersBase = super.vscode.override { isInsiders = true; };
  vscode = self.vscodeInsidersBase.overrideAttrs (old: {
    src = (
      builtins.fetchTarball {
        url = "https://code.visualstudio.com/sha/download?build=insider&os=linux-x64";
        sha256 = "0ngh4nm7v89waikans19n0lpga7ssq71kxr3z9cmi2p2cc1idn7n";
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
        # Native deps for the bundled @github/copilot "computer use" module
        # (computer.node): X11 input injection, screenshot JPEG encoding, and
        # Wayland screen capture / input emulation.
        self.libxtst
        self.pipewire
        self.libei
        (self.libjpeg_turbo.override { enableJpeg8 = true; })
      ];
  });
}
