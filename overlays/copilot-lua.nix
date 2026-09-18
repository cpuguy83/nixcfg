final: prev: {
  vimPlugins = prev.vimPlugins.extend (
    _vimFinal: vimPrev: {
      copilot-lua =
        if vimPrev.copilot-lua.version != "2.0.4" then
          vimPrev.copilot-lua
        else
          vimPrev.copilot-lua.overrideAttrs {
            # The v2.0.4 tag moved; preserve the original source and its bundled LSP.
            src = final.fetchFromGitHub {
              owner = "zbirenbaum";
              repo = "copilot.lua";
              rev = "407349117f176789df6ec1c23bca72f34e15b4e8";
              hash = "sha256-+hQ4Og0ZZS/tvs4z5733qRu5+W4D24HgHHPIL5vd0Eo=";
            };
          };
    }
  );
}
