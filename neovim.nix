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

    plugins.telescope.enable = true;
    # Needed by telescope
    plugins.web-devicons.enable = true;

    plugins.copilot-lsp.enable = true;
    plugins.copilot-chat.enable = true;
    plugins.copilot-lua = {
      enable = true;
      settings.suggestion = {
        enabled = true;
        auto_trigger = false;
      };
      settings.panel.enabled = true;
    };

    plugins.cmp = {
      enable = true;
      settings = {
        sources = [
          { name = "nvim_lsp"; }
          { name = "path"; }
          { name = "buffer"; }
          { name = "luasnip"; }
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
      vim-nix
      vim-go
      vim-toml
      molokai
      nerdtree
      vim-fugitive
      vim-sensible
      coc-nvim
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

    extraConfigLua = ''
      vim.keymap.set("i", "<Tab>", function()
        local copilot = require("copilot.suggestion")
        if copilot.is_visible() then
          copilot.accept()
        else
          return vim.api.nvim_replace_termcodes("<Tab>", true, true, true)
        end
      end, { expr = true })
    '';

    keymaps = [
      {
        key = "<C-p>";
        action = ''<cmd>lua require("telescope.builtin").find_files()<CR>'';
      }
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
