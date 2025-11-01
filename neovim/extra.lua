vim.keymap.set("i", "<Tab>", function()
	local copilot = require("copilot.suggestion")
	if copilot.is_visible() then
		copilot.accept()
	else
		return vim.api.nvim_replace_termcodes("<Tab>", true, true, true)
	end
end, { expr = true })
