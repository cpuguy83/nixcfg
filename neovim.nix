{ pkgs, pkgs-unstable, ... }:

{
  home.packages = with pkgs-unstable; [
    ripgrep
    nixd
    nixfmt-rfc-style
  ];

  programs.nixvim = {
    enable = true;

    clipboard.providers.wl-copy.enable = true;

    plugins.notify.enable = true;
    plugins.git-conflict.enable = true;
    plugins.gitblame.enable = true;
    plugins.lightline.enable = true;
    plugins.treesitter.enable = true;
    plugins.neogit.enable = true;

    plugins.nix.enable = true;

    plugins.telescope = {
      enable = true;
      luaConfig.post = builtins.readFile ./neovim/telescope.lua;
    };
    # Needed by telescope
    plugins.web-devicons.enable = true;

    plugins.copilot-lsp.enable = true;
    plugins.copilot-chat.enable = true;
    plugins.copilot-cmp.enable = true;
    plugins.copilot-lua = {
      enable = true;
      settings.suggestion = {
        enabled = false;
        auto_trigger = false;
      };
      settings.panel.enabled = false;
    };

    plugins.coq-nvim.enable = true;

    plugins.cmp = {
      enable = true;
      autoEnableSources = true;
      settings = {
        sources = [
          { name = "nvim_lsp"; }
          { name = "path"; }
          { name = "buffer"; }
          { name = "luasnip"; }
          { name = "copilot"; }
        ];

        mapping = {
          "<C-d>" = "cmp.mapping.scroll_docs(-4)";
          "<C-e>" = "cmp.mapping.close()";
          "<C-f>" = "cmp.mapping.scroll_docs(4)";
          "<CR>" = "cmp.mapping.confirm({ select = true })";
          "<S-Tab>" = "cmp.mapping(cmp.mapping.select_prev_item(), {'i', 's'})";
          "<Tab>" = "cmp.mapping(cmp.mapping.select_next_item(), {'i', 's'})";
        };
      };
    };

    plugins.cmp-nvim-lsp.enable = true;

    plugins.yazi = {
      enable = true;
      settings = {
        enable_mouse_support = true;
      };
      luaConfig.post = builtins.readFile ./neovim/yazi.lua;
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

    extraConfigLua = builtins.readFile ./neovim/extra.lua;

    keymaps = [
      {
        mode = "i";
        key = "<C-Space>";
        action = ''<cmd>lua require("copilot.suggestion").next()<CR>'';
      }
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
    ];
  };
}
