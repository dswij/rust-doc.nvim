# rust-doc.nvim

Search and open Rust documentation (your crate, its dependencies, and the
standard library) from Neovim. A Lua port of
[rhysd/rust-doc.vim](https://github.com/rhysd/rust-doc.vim).

`cargo doc` generates HTML but gives you no way to search it. This plugin
indexes the generated docs and opens the page you want in your browser.

## Requirements

- Neovim 0.10+ (`vim.system`, `vim.ui.open`, `vim.fn.getregion`)
- `cargo` for project docs (`target/doc` is generated automatically if missing)
- `rustup` with the `rust-docs` component for std docs
  (`rustup component add rust-docs`)

## Installation

lazy.nvim:

```lua
{
  'dswij/rust-doc.nvim',   -- or a local path via `dir = '~/imp/rust-doc.nvim'`
  ft = 'rust',
  cmd = { 'RustDoc', 'RustDocFuzzy', 'RustDocModule', 'RustDocPick', 'RustDocGenerate' },
  opts = {},               -- see Configuration
}
```

Without a plugin manager, put the directory on your `runtimepath` and call
`require('rust-doc').setup()`. `setup()` is optional; defaults apply without it.

## Usage

All commands work from any file inside a Cargo project (the project is found by
walking up from the current buffer to the outermost workspace `Cargo.toml`).
If `target/doc` does not exist yet, `cargo doc` runs first (asynchronously).

| Command | Description |
| --- | --- |
| `:RustDoc {crate-or-module} [{item}]` | Open an exact crate/module, or an item in it. `<Tab>` completes both arguments. |
| `:RustDocFuzzy {identifier}` | Search all modules and items for a word. Opens directly if unambiguous, else shows a picker. |
| `:RustDocModule {name}` | Same as above, but only module/crate names. |
| `:RustDocPick [modules]` | Pick from every page with `vim.ui.select`. Pass `modules` for a faster, module-only list. |
| `:RustDocGenerate` | Run `cargo doc` for the current project. |

### Examples

Assuming your crate depends on `rand`:

```vim
:RustDoc rand                  " crate rand
:RustDoc rand::distributions   " module
:RustDoc rand Rng              " trait rand::Rng
:RustDoc std::vec              " standard library
:RustDocFuzzy Standard         " every item named Standard
:RustDocModule io              " std::io, std::io::prelude, ...
```

### Mapping `K`

Set `map_K = true` to make `K` open the docs for the word under the cursor
(or the visual selection) in Rust buffers. It is off by default because it
replaces Neovim's LSP hover on `K`. You can also bind your own key:

```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'rust',
  callback = function(ev)
    vim.keymap.set({ 'n', 'x' }, '<leader>rd', '<Plug>(rust-doc-search)', { buffer = ev.buf })
  end,
})
```

### Picker integration (replaces the unite/denite sources)

`:RustDocPick` uses `vim.ui.select`, so any plugin that overrides it
(telescope-ui-select, fzf-lua, snacks.picker, mini.pick, dressing.nvim) gives
you a fuzzy finder over all docs.

### Lua API

```lua
local rd = require('rust-doc')
rd.open('rand', 'Rng')
rd.search('Rng')
rd.search_module('std::io')
rd.pick()         -- rd.pick(true) for modules only
rd.generate_current()
```

## Configuration

Defaults:

```lua
require('rust-doc').setup({
  open_cmd = nil,        -- string | string[] | fun(url): command or function used to open the URL
  vim_open_cmd = nil,    -- Ex command to open the URL inside Neovim, e.g. 'edit' or 'W3m'
  std_doc_dir = nil,     -- directory with downloaded std docs (skips rustup detection)
  search_std = true,     -- also search std, core, alloc, proc_macro, test
  list_on_miss = true,   -- show a picker when nothing matches
  auto_generate = true,  -- run `cargo doc` if the project has no docs yet
  cargo_doc_args = {},   -- e.g. { '--no-deps', '--all-features' }
  map_K = false,         -- map K in Rust buffers
})
```

Opening order: `vim_open_cmd`, then `open_cmd`, then `vim.ui.open()` (xdg-open,
open, or the Windows shell handler).

```lua
open_cmd = { 'firefox', '--new-tab' }
open_cmd = function(url) vim.system({ 'w3m', url }) end
```

## Differences from rust-doc.vim

- Lua, with `setup()` instead of `g:rust_doc#...` variables.
- Asynchronous `cargo doc`; no blocking `!cargo doc`.
- Uses `cargo metadata` / `CARGO_TARGET_DIR`, so a custom target directory works.
- `vim.ui.select` replaces the `input()` prompts and the unite/denite sources.
- `K` mapping is opt-in.
- Std docs are limited to std, core, alloc, proc_macro and test (not the book etc.).
- `:RustDocGenerate` and `<Plug>(rust-doc-search)` are new.
- Option mapping: `vim_open_cmd`, `open_cmd`, `define_map_K` -> `map_K`,
  `do_not_ask_for_module_list` -> `list_on_miss` (inverted),
  `downloaded_rust_doc_dir` -> `std_doc_dir`.

See `:help rust-doc` for the full reference.

## License

MIT. Derived from rust-doc.vim by rhysd.
