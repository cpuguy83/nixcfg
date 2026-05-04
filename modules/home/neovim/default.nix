{
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:

{

  home.packages = with pkgs-unstable; [
    ripgrep
    nixd
    nixfmt
  ];

  programs.bash.bashrcExtra = lib.mkAfter ''
    export EDITOR=nvim
  '';

  programs.nixvim = {
    enable = true;

    clipboard.providers.wl-copy.enable = true;

    plugins.notify.enable = true;
    # plugins.git-conflict.enable = true;
    plugins.gitblame.enable = true;
    plugins.lightline.enable = true;
    plugins.treesitter.enable = true;
    plugins.neogit.enable = true;
    plugins.diffview.enable = true;

    plugins.nix.enable = true;

    plugins.telescope = {
      enable = true;
      luaConfig.post = builtins.readFile ./telescope.lua;
    };
    # Needed by telescope
    plugins.web-devicons.enable = true;

    plugins.copilot-lsp.enable = false;
    plugins.copilot-chat.enable = true;
    plugins.copilot-cmp.enable = false;
    plugins.copilot-lua = {
      enable = true;
      settings.suggestion.enabled = false;
      settings.panel.enabled = false;
    };

    plugins.coq-nvim.enable = false;

    plugins.blink-cmp-copilot.enable = true;
    plugins.blink-cmp = {
      enable = true;
      settings = {
        keymap = {
          "<Tab>" = [
            "select_next"
            "snippet_forward"
            "fallback"
          ];
          "<S-Tab>" = [
            "select_prev"
            "snippet_backward"
            "fallback"
          ];
          "<CR>" = [
            "accept"
            "fallback"
          ];
          "<C-e>" = [
            "hide"
            "fallback"
          ];
          "<C-space>" = [
            "show"
            "show_documentation"
            "hide_documentation"
          ];
        };
        completion = {
          documentation.auto_show = true;
          ghost_text.enabled = true;
        };
        signature.enabled = true;
        sources = {
          default = [
            "lsp"
            "path"
            "buffer"
            "copilot"
          ];
          providers.copilot = {
            async = true;
            module = "blink-cmp-copilot";
            name = "copilot";
            score_offset = 100;
          };
        };
      };
    };

    plugins.cmp.enable = false;
    plugins.cmp-nvim-lsp.enable = false;

    plugins.yazi = {
      enable = true;
      settings = {
        enable_mouse_support = true;
      };
      luaConfig.post = builtins.readFile ./yazi.lua;
    };

    plugins.dap = {
      enable = true;
    };

    plugins.dap-go = {
      enable = true;
    };

    plugins.dap-ui = {
      enable = false;
    };

    plugins.dap-view = {
      enable = true;
    };

    plugins.conform-nvim = {
      enable = true;
      settings.format_on_save = {
        lsp_fallback = true;
      };

      settings.formatters_by_ft = {
        nix = [ "nixfmt" ];
        go = [ "goimports" ];
      };
    };

    plugins.lsp = {
      enable = true;
      servers = {
        gopls = {
          enable = true;
          filetypes = [
            "go"
            "gomod"
          ];
        };

        jqls = {
          enable = true;
          filetypes = [ "jq" ];
        };

        lua_ls = {
          enable = true;
          filetypes = [ "lua" ];
        };

        nixd = {
          enable = true;
          filetypes = [ "nix" ];
        };

        docker_language_server = {
          enable = true;
          filetypes = [ "dockerfile" ];
        };
      };
    };

    extraPlugins = with pkgs.vimPlugins; [
      vim-go
      vim-toml
      molokai
      vim-sensible
    ];

    colorscheme = "molokai";

    opts = {
      number = true;
      relativenumber = true;
      tabstop = 2;
      shiftwidth = 2;
      mouse = "a";
      list = true;
      listchars = "tab:▸ ";
    };

    extraConfigLua = builtins.readFile ./extra.lua;

    keymaps = [

      {
        mode = "n";
        key = "<leader>b";
        action = "<cmd>DapToggleBreakpoint<CR>";
      }
      {
        mode = "n";
        key = "<leader>gs";
        action = "<cmd>Neogit<CR>";
      }
      {
        mode = "n";
        key = "<leader>diff";
        action = "<cmd>DiffviewOpen<CR>";
      }
      {
        mode = "n";
        key = "<leader>yy";
        action = "<cmd>Yazi<CR>";
      }
    ];
  };
}
