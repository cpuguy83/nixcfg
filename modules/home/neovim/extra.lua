vim.g.loaded_netrwPlugin = 1

vim.keymap.set('n', '<leader>gb', function()
  local file = vim.api.nvim_buf_get_name(0)
  if file == '' then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local dir = vim.fn.fnamemodify(file, ':h')
  local name = vim.fn.fnamemodify(file, ':t')

  local result = vim
    .system(
      { 'git', 'blame', '-L', lnum .. ',' .. lnum, '--porcelain', '--', name },
      { cwd = dir, text = true }
    )
    :wait()

  if result.code ~= 0 then
    vim.notify('git blame failed: ' .. (result.stderr or ''), vim.log.levels.ERROR)
    return
  end

  local sha = result.stdout:match('^(%x+)')
  if not sha or sha:match('^0+$') then
    vim.notify('No commit for this line (uncommitted change)', vim.log.levels.WARN)
    return
  end

  vim.cmd.DiffviewOpen(sha .. '^!')
end, { desc = 'Jump to the commit that changed this line' })
