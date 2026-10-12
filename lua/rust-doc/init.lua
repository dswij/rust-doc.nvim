local docs = require('rust-doc.docs')

local M = {}

---@class RustDocOptions
---@field open_cmd string|string[]|fun(url: string)|nil  external command (or function) used to open a document URL
---@field vim_open_cmd string|nil     Ex command used to open the URL inside Neovim, e.g. "edit" with a w3m plugin
---@field std_doc_dir string|nil      directory of downloaded std docs (overrides rustup auto-detection)
---@field search_std boolean          also search std/core/alloc docs
---@field list_on_miss boolean        offer a picker when nothing matches
---@field auto_generate boolean       run `cargo doc` when the project has no docs yet
---@field cargo_doc_args string[]     extra arguments for `cargo doc`
---@field map_K boolean               map K in Rust buffers
M.defaults = {
  open_cmd = nil,
  vim_open_cmd = nil,
  std_doc_dir = nil,
  search_std = true,
  list_on_miss = true,
  auto_generate = true,
  cargo_doc_args = {},
  map_K = false,
}

M.options = vim.deepcopy(M.defaults)

local function notify(msg, level)
  vim.notify('rust-doc: ' .. msg, level or vim.log.levels.INFO)
end

local function hint_dir()
  local d = vim.fn.expand('%:p:h')
  if d == '' or vim.fn.isdirectory(d) == 0 then
    d = vim.fn.getcwd()
  end
  return d
end

local function map_K_in_buffer(buf)
  vim.keymap.set('n', 'K', function()
    M.search(vim.fn.expand('<cword>'))
  end, { buffer = buf, silent = true, desc = 'Open Rust documentation' })
  vim.keymap.set('x', 'K', function()
    M.search(M.visual_text())
  end, { buffer = buf, silent = true, desc = 'Open Rust documentation' })
end

---@param opts RustDocOptions?
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', M.defaults, opts or {})
  local group = vim.api.nvim_create_augroup('rust-doc', { clear = true })
  if M.options.map_K then
    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      pattern = 'rust',
      callback = function(ev)
        map_K_in_buffer(ev.buf)
      end,
    })
    -- Cover Rust buffers that were opened before setup() ran.
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[b].filetype == 'rust' then
        map_K_in_buffer(b)
      end
    end
  end
end

---@return string
function M.visual_text()
  local ok, lines = pcall(vim.fn.getregion, vim.fn.getpos('v'), vim.fn.getpos('.'), { type = vim.fn.mode() })
  if not ok then
    return ''
  end
  return vim.trim(table.concat(lines, ' '))
end

--- Opens a documentation entry using the configured method.
---@param entry RustDocEntry
function M.open_entry(entry)
  local o = M.options
  local url = 'file://' .. vim.fn.fnamemodify(entry.path, ':p')
  notify(("opening '%s'"):format(entry.name))

  if o.vim_open_cmd and o.vim_open_cmd ~= '' then
    vim.cmd(o.vim_open_cmd .. ' ' .. vim.fn.fnameescape(url))
  elseif type(o.open_cmd) == 'function' then
    o.open_cmd(url)
  elseif o.open_cmd and o.open_cmd ~= '' and #o.open_cmd > 0 then
    local cmd = type(o.open_cmd) == 'table' and vim.list_extend({}, o.open_cmd) or vim.split(o.open_cmd, '%s+')
    table.insert(cmd, url)
    vim.system(cmd, { detach = true }, function(res)
      if res.code ~= 0 then
        vim.schedule(function()
          notify(('`%s` failed: %s'):format(table.concat(cmd, ' '), res.stderr or ''), vim.log.levels.ERROR)
        end)
      end
    end)
  else
    local _, err = vim.ui.open(url)
    if err then
      notify('failed to open ' .. url .. ': ' .. err, vim.log.levels.ERROR)
    end
  end
end

local function format_entry(e)
  return e.kind and ('%s  [%s]'):format(e.name, e.kind) or e.name
end

---@param list RustDocEntry[]
---@param prompt string
local function pick(list, prompt)
  vim.ui.select(list, { prompt = prompt, format_item = format_entry }, function(choice)
    if choice then
      M.open_entry(choice)
    end
  end)
end

--- Runs `cargo doc` for the project at `root`, then calls `cb`.
---@param root string
---@param cb fun()?
function M.generate(root, cb)
  if vim.fn.executable('cargo') == 0 then
    return notify('`cargo` is not executable', vim.log.levels.ERROR)
  end
  local cmd = vim.list_extend({ 'cargo', 'doc' }, M.options.cargo_doc_args)
  notify('running `' .. table.concat(cmd, ' ') .. '` ...')
  vim.system(cmd, { cwd = root, text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        notify('`cargo doc` failed:\n' .. (res.stderr or ''), vim.log.levels.ERROR)
      else
        notify('`cargo doc` finished')
        if cb then
          cb()
        end
      end
    end)
  end)
end

--- Calls `cb(dirs)` with the available doc directories, generating project
--- docs first when needed.
---@param cb fun(dirs: { dir: string, std: boolean }[])
local function with_docs(cb)
  local dirs, root, project_doc = docs.resolve(hint_dir(), M.options)
  local missing_project = root and project_doc and not (vim.uv or vim.loop).fs_stat(project_doc)
  if missing_project and M.options.auto_generate then
    return M.generate(root, function()
      cb((docs.resolve(hint_dir(), M.options)))
    end)
  end
  if #dirs == 0 then
    return notify(
      root and 'no documentation found. Run :RustDocGenerate' or 'Cargo.toml and std docs not found',
      vim.log.levels.ERROR
    )
  end
  cb(dirs)
end

local function not_found(what, candidates)
  if M.options.list_on_miss and #candidates > 0 then
    pick(candidates, ("No document for '%s'. Choose:"):format(what))
  else
    notify(("no document found for '%s'"):format(what), vim.log.levels.WARN)
  end
end

--- Opens `module` (a crate or module path) or `module`'s `identifier`.
---@param module string
---@param identifier string?
function M.open(module, identifier)
  with_docs(function(dirs)
    local modules = docs.entries(dirs, false)
    local found
    for _, m in ipairs(modules) do
      if m.name == module then
        found = m
        break
      end
    end
    if not found then
      return not_found(module, modules)
    end
    if not identifier then
      return M.open_entry(found)
    end
    local items = docs.module_items(found)
    for _, i in ipairs(items) do
      if i.name == identifier then
        return M.open_entry({ name = found.name .. '::' .. i.name, path = i.path, kind = i.kind })
      end
    end
    local full = {}
    for _, i in ipairs(items) do
      full[#full + 1] = { name = found.name .. '::' .. i.name, path = i.path, kind = i.kind }
    end
    not_found(module .. '::' .. identifier, full)
  end)
end

local function fuzzy(candidates, query)
  if query == '' then
    return notify('empty query', vim.log.levels.WARN)
  end
  local pat = '%f[%w_]' .. vim.pesc(query) .. '%f[^%w_]'
  local found = {}
  for _, c in ipairs(candidates) do
    if c.name == query then
      return M.open_entry(c)
    elseif c.name:find(pat) then
      found[#found + 1] = c
    end
  end
  if #found == 0 then
    return notify(("no document found for '%s'"):format(query), vim.log.levels.WARN)
  elseif #found == 1 then
    return M.open_entry(found[1])
  end
  pick(found, ("Documents matching '%s':"):format(query))
end

--- Fuzzy search of modules and items; opens instantly if unambiguous.
---@param query string
function M.search(query)
  query = vim.trim(query or '')
  if query == '' then
    return notify('no identifier under the cursor', vim.log.levels.WARN)
  end
  with_docs(function(dirs)
    fuzzy(docs.entries(dirs, true), query)
  end)
end

--- Fuzzy search of module names only.
---@param query string
function M.search_module(query)
  with_docs(function(dirs)
    fuzzy(docs.entries(dirs, false), vim.trim(query))
  end)
end

--- Lists every candidate via vim.ui.select.
---@param modules_only boolean?
function M.pick(modules_only)
  with_docs(function(dirs)
    pick(docs.entries(dirs, not modules_only), 'Rust docs:')
  end)
end

--- `cargo doc` for the project of the current buffer.
function M.generate_current()
  local root = docs.find_project_root(hint_dir())
  if not root then
    return notify('Cargo.toml is not found', vim.log.levels.ERROR)
  end
  M.generate(root)
end

-- Command-line completion (synchronous; never triggers `cargo doc`).
function M.complete(_, cmdline)
  local args = vim.split(cmdline, '%s+')
  local dirs = docs.resolve(hint_dir(), M.options)
  local modules = docs.entries(dirs, false)
  local out = {}
  if #args == 2 then
    for _, m in ipairs(modules) do
      if vim.startswith(m.name, args[2]) then
        out[#out + 1] = m.name
      end
    end
  elseif #args == 3 then
    for _, m in ipairs(modules) do
      if m.name == args[2] then
        for _, i in ipairs(docs.module_items(m)) do
          if vim.startswith(i.name, args[3]) then
            out[#out + 1] = i.name
          end
        end
        break
      end
    end
  end
  table.sort(out)
  return out
end

function M.complete_module(_, cmdline)
  local args = vim.split(cmdline, '%s+')
  if #args ~= 2 then
    return {}
  end
  return vim.tbl_filter(function(n)
    return vim.startswith(n, args[2])
  end, vim.tbl_map(function(m)
    return m.name
  end, docs.entries((docs.resolve(hint_dir(), M.options)), false)))
end

return M
