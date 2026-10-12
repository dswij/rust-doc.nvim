if vim.g.loaded_rust_doc or vim.fn.has('nvim-0.10') == 0 then
  return
end
vim.g.loaded_rust_doc = true

local function rd()
  return require('rust-doc')
end

vim.api.nvim_create_user_command('RustDoc', function(c)
  rd().open(c.fargs[1], c.fargs[2])
end, {
  nargs = '+',
  complete = function(...)
    return rd().complete(...)
  end,
  desc = 'Open docs for a crate/module, optionally an item in it',
})

vim.api.nvim_create_user_command('RustDocFuzzy', function(c)
  rd().search(c.args)
end, { nargs = 1, desc = 'Fuzzy search docs for an identifier' })

vim.api.nvim_create_user_command('RustDocModule', function(c)
  rd().search_module(c.args)
end, {
  nargs = 1,
  complete = function(...)
    return rd().complete_module(...)
  end,
  desc = 'Search docs for a module',
})

vim.api.nvim_create_user_command('RustDocPick', function(c)
  rd().pick(c.args == 'modules')
end, {
  nargs = '?',
  complete = function()
    return { 'modules' }
  end,
  desc = 'Pick any doc page via vim.ui.select',
})

vim.api.nvim_create_user_command('RustDocGenerate', function()
  rd().generate_current()
end, { nargs = 0, desc = 'Run `cargo doc` for the current project' })

vim.keymap.set('n', '<Plug>(rust-doc-search)', function()
  rd().search(vim.fn.expand('<cword>'))
end, { desc = 'rust-doc: search word under cursor' })
vim.keymap.set('x', '<Plug>(rust-doc-search)', function()
  rd().search(rd().visual_text())
end, { desc = 'rust-doc: search selection' })
