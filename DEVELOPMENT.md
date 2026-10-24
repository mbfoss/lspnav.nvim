# Development

Technical notes for working on lspnav.nvim.

## Requirements

- Neovim >= 0.11 (enforced at load time in [`plugin/lspnav.lua`](plugin/lspnav.lua))
- [busted](https://lunarmodules.github.io/busted/) for the test suite,
  installed for Lua 5.1 (see below)

## Testing

Tests use [busted](https://lunarmodules.github.io/busted/), are kept in
[`tests/`](tests/) and are discovered through [`.busted`](.busted). They run
through [`tests/nvim-lua`](tests/nvim-lua), so each spec executes inside a real
Neovim and can use the `vim` API.

```bash
# Run the whole suite
make test

# Pass flags through to busted
make test BUSTED_ARGS="--filter=symboltree -o gtest"
make test BUSTED_ARGS=tests/calltree_spec.lua
```

busted must already be installed for Lua 5.1, the version Neovim embeds:
`luarocks --lua-version=5.1 --local install busted`. `make test` fails if it is
missing rather than installing it. The runner is in the
[`Makefile`](Makefile); [`tests/init.lua`](tests/init.lua) is the busted helper
that puts the plugin on the runtimepath.

## Demo

The GIF at the top of the README is recorded from
[`data/demo/demo.scene`](data/demo/demo.scene) with
[nvim-demo](https://github.com/mbfoss/nvim-demo-tool). The scene drives a
scripted Neovim session against [`data/demo/sample.c`](data/demo/sample.c), which clangd
indexes so the symbol tree, references, and call hierarchy all have data.

```bash
scripts/demo.sh                      # every data/demo/*.scene
scripts/demo.sh data/demo/demo.scene      # one scene
```

The script clones nvim-demo into
`${XDG_CACHE_HOME:-~/.cache}/lspnav.nvim/nvim-demo-tool` when it is not
installed; set `NVIM_DEMO` to a checkout's `bin/nvim-demo` to use that instead.
It needs Neovim, agg, pyte, and clangd, and writes the GIF and cast to
`data/demo/out/` (ignored by Git).

The rendered GIF lives on the orphan `assets` branch at its root, and the
README links to the raw file there. After re-recording, copy
`data/demo/out/lspnav.gif` over `lspnav.gif` on `assets` and push that branch.

## Architecture

Self-contained feature modules under [`lua/lspnav/`](lua/lspnav/). Each
(`lspnav.motions`, `lspnav.symboltree`, ...) exposes `setup(opts)` and can be
required directly, with no dependency on the others.

### The aggregator

[`lua/lspnav/init.lua`](lua/lspnav/init.lua) is an optional entry point for a
single `require("lspnav").setup({...})` call:

- Each key in the user table names an `lspnav.<name>` module, required on
  demand; there is no module list to maintain.
- The value is that module's options table. There is no enable/disable flag:
  side-window modules load on first use, and `motions` is only called as
  functions.
- A key that names no module with a `setup()`, or a value that is not a table,
  produces a warning; unmentioned modules are never touched.

Adding a module means writing `lua/lspnav/<name>.lua` with a `setup(opts)`
function; nothing needs to be registered.

### Shared toolkit (`util`)

[`lua/lspnav/util/`](lua/lspnav/util/) holds the primitives the modules build on:
the tree buffer and tree type, fixed/floating windows, hover, config merging,
user-command registration, an LRU cache, throttle, and the
`textDocument/documentSymbol` helpers (`lspnav.util.lspsymbols`).

The tree primitives were copied from
[keystone.nvim](https://github.com/mbfoss/keystone.nvim), by the same author.
The two plugins are independent: neither installs the other, and the copies may
diverge. Keep this copy internally consistent rather than syncing it.

A `util` module carries no policy of its own: it takes what its caller passes,
returns a value, and registers nothing. Anything two features need goes here
rather than into whichever feature needs it first.

### Lazy loading

`:Lspnav` is registered in `plugin/lspnav.lua` without loading any Lua;
`lspnav` and `lspnav.util.usercmd` are required on first use. The first
argument selects the feature module (`:Lspnav symboltree ...`), which is
required on first run, and `lspnav.<module>.command` implements that
subcommand. Motion actions (`:Lspnav next_function`) call `lspnav.motions`
directly. A module not yet configured is activated with its defaults, so the
command works from a bare install. The command body runs its implementation
through `pcall` and reports a raised error with `vim.notify`; completion
delegates to `lspnav.util.usercmd`.

### Highlight groups

The modules define `LspnavSymbolTree*`, `LspnavCallTree*` and `LspnavReferences*`
groups, plus the `LspnavIndentGuide` group shared by every tree window. They are
separate from keystone's groups so both plugins can be installed at once.
