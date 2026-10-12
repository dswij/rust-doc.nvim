-- Discovery of rustdoc output: locating doc directories and enumerating
-- the modules / items inside them.
local M = {}

local uv = vim.uv or vim.loop

local STD_CRATES = { std = true, core = true, alloc = true, proc_macro = true, test = true }
-- Directories rustdoc generates that never contain documentation pages.
local SKIP_DIRS = {
  src = true,
  ['static.files'] = true,
  implementors = true,
  ['search.desc'] = true,
}

local cache = { target = {}, std = nil }

local function is_dir(p)
  local st = p and uv.fs_stat(p)
  return st ~= nil and st.type == 'directory'
end

local function run(cmd, cwd)
  local ok, res = pcall(function()
    return vim.system(cmd, { text = true, cwd = cwd }):wait(10000)
  end)
  if ok and res and res.code == 0 then
    return vim.trim(res.stdout or '')
  end
end

local function has_workspace(cargo)
  local f = io.open(cargo, 'r')
  if not f then
    return false
  end
  local found = false
  for line in f:lines() do
    if line:match('^%s*%[workspace%]') then
      found = true
      break
    end
  end
  f:close()
  return found
end

--- Finds the root directory of the Cargo project containing `dir`.
--- A workspace root wins over the nearest package manifest.
---@param dir string
---@return string? root
function M.find_project_root(dir)
  local manifests = vim.fs.find('Cargo.toml', { upward = true, path = dir, limit = math.huge, type = 'file' })
  if #manifests == 0 then
    return nil
  end
  for _, m in ipairs(manifests) do
    if has_workspace(m) then
      return vim.fs.dirname(m)
    end
  end
  return vim.fs.dirname(manifests[1])
end

---@param root string
---@return string target_dir
function M.target_dir(root)
  local env = vim.env.CARGO_TARGET_DIR
  if env and env ~= '' then
    return vim.fn.fnamemodify(env, ':p')
  end
  if cache.target[root] then
    return cache.target[root]
  end
  local dir = root .. '/target'
  if vim.fn.executable('cargo') == 1 then
    local out = run({ 'cargo', 'metadata', '--no-deps', '--format-version', '1', '--offline' }, root)
    local ok, meta = pcall(vim.json.decode, out or '')
    if ok and type(meta) == 'table' and meta.target_directory then
      dir = meta.target_directory
    end
  end
  cache.target[root] = dir
  return dir
end

---@param opts table plugin options
---@return string? dir directory holding the std/core/alloc docs
function M.std_doc_dir(opts)
  if opts.std_doc_dir and opts.std_doc_dir ~= '' then
    local d = vim.fn.expand(opts.std_doc_dir)
    return is_dir(d) and d or nil
  end
  if cache.std ~= nil then
    return cache.std or nil
  end
  local found = false
  if vim.fn.executable('rustup') == 1 then
    local index = run({ 'rustup', 'doc', '--path' })
    if index and vim.fn.filereadable(index) == 1 then
      found = vim.fs.dirname(index)
    end
  end
  if not found and vim.fn.executable('rustc') == 1 then
    local sysroot = run({ 'rustc', '--print', 'sysroot' })
    local d = sysroot and (sysroot .. '/share/doc/rust/html')
    if is_dir(d) then
      found = d
    end
  end
  cache.std = found
  return found or nil
end

--- Resolves the documentation directories relevant to `hint`.
--- Project docs come first so they take priority over the standard library.
---@param hint string a directory (usually the current buffer's directory)
---@param opts table plugin options
---@return { dir: string, std: boolean }[] dirs
---@return string? root project root, when inside a Cargo project
---@return string? project_doc where project docs are/should be generated
function M.resolve(hint, opts)
  local dirs = {}
  local root = M.find_project_root(hint)
  local project_doc
  if root then
    project_doc = M.target_dir(root) .. '/doc'
    if is_dir(project_doc) then
      dirs[#dirs + 1] = { dir = project_doc, std = false }
    end
  end
  if opts.search_std then
    local std = M.std_doc_dir(opts)
    if std then
      dirs[#dirs + 1] = { dir = std, std = true }
    end
  end
  return dirs, root, project_doc
end

---@class RustDocEntry
---@field name string   e.g. "std::vec::Vec"
---@field path string   absolute path to the html file
---@field kind string?  "struct", "trait", "fn", ... ; nil for modules

local function scan(dir, prefix, crates, mods, items)
  for name, t in vim.fs.dir(dir) do
    if t == 'directory' then
      local top = prefix == ''
      if not SKIP_DIRS[name] and not name:find('.', 1, true) and not (top and crates and not crates[name]) then
        local sub = top and name or (prefix .. '::' .. name)
        local index = dir .. '/' .. name .. '/index.html'
        if uv.fs_stat(index) then
          mods[#mods + 1] = { name = sub, path = index }
        end
        scan(dir .. '/' .. name, sub, crates, mods, items)
      end
    elseif prefix ~= '' then
      local kind, item = name:match('^(%a+)%.(.+)%.html$')
      if kind then
        items[#items + 1] = { name = prefix .. '::' .. item, path = dir .. '/' .. name, kind = kind }
      end
    end
  end
end

--- Lists modules (and optionally items) in the given doc directories.
---@param dirs { dir: string, std: boolean }[]
---@param with_items boolean
---@return RustDocEntry[]
function M.entries(dirs, with_items)
  local out = {}
  for _, d in ipairs(dirs) do
    local mods, items = {}, {}
    scan(d.dir, '', d.std and STD_CRATES or nil, mods, items)
    vim.list_extend(out, mods)
    if with_items then
      vim.list_extend(out, items)
    end
  end
  return out
end

--- Lists the items documented directly in a module.
---@param module RustDocEntry
---@return RustDocEntry[]
function M.module_items(module)
  local out = {}
  local dir = vim.fs.dirname(module.path)
  for name, t in vim.fs.dir(dir) do
    if t == 'file' then
      local kind, item = name:match('^(%a+)%.(.+)%.html$')
      if kind then
        out[#out + 1] = { name = item, path = dir .. '/' .. name, kind = kind }
      end
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

return M
