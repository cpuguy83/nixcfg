{ pkgs, pkgs-unstable, inputs, ... }:

{
  imports = [ inputs.nixvim.homeModules.nixvim ];
  home.pointerCursor = {
    enable = true;
    package = pkgs.whitesur-cursors;
    name = "WhiteSur-cursors";
    size = 24;
    gtk.enable = true;
  };

  home.packages = with pkgs; [
    whitesur-gtk-theme
    whitesur-icon-theme
    whitesur-cursors

    pkgs-unstable.codex
    pkgs-unstable.claude-code

    ripgrep
  ];

  gtk = {
    enable = true;
    theme = {
      package = pkgs.whitesur-gtk-theme;
      name = "WhiteSur-Light";
    };
    iconTheme = {
      package = pkgs.whitesur-icon-theme;
      name = "WhiteSur-Light";
    };
    cursorTheme = {
      package = pkgs.whitesur-cursors;
      name = "WhiteSur-cursors-light";
    };
  };

  programs.nixvim = {
    enable = true;
    plugins.lightline.enable = true;
    plugins.treesitter.enable = true;

    extraPlugins = with pkgs.vimPlugins; [
      vim-nix
      vim-go
      vim-toml
      neovim-fuzzy
      molokai
      nerdtree
    ];

    colorscheme = "molokai";

    opts = {
      number = true;
      relativenumber = true;
      tabstop = 2;
      shiftwidth = 2;
      mouse = "a";
      ttymouse = "sgr";
    };

    keymaps = [
      {
        key = "<C-p>";
        action = "<cmd>FuzzyOpen<CR>";
      }
    ];
  };
}
