require("telescope").setup {
	defaults = {
		file_ignore_patterns = { "^%.git/" }
	},
	pickers = {
		find_files = {
			hidden = true
		},
		live_grep = {
			additional_args = function(opts)
				return {"--hidden"}
			end
		}
	}
}

local telescope_builtin = require('telescope.builtin')
vim.keymap.set('', '<leader>fg', telescope_builtin.live_grep, {})
vim.keymap.set('', '<leader>ff', telescope_builtin.find_files, {})
vim.keymap.set('', '<c-p>', telescope_builtin.find_files, {})
