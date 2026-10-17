# Attributions

## Bundled data

- **[Nerd Fonts](https://github.com/ryanoasis/nerd-fonts)** (MIT): the icon
  glyphs in `lua/lspnav/symboltree/kinds.lua` are Nerd Fonts codepoints. No font
  file is bundled; the table only references codepoints, rendered by the user's
  own patched font.

## Development-time only (not distributed)

- **[panvimdoc](https://github.com/kdheepak/panvimdoc)** (MIT): generated
  `doc/lspnav*.txt` from the Markdown docs.
- **[busted](https://github.com/lunarmodules/busted)** and
  **[luassert](https://github.com/lunarmodules/luassert)** (MIT), and
  **[nlua](https://github.com/mfussenegger/nlua)** (GPL-3.0): the test
  toolchain. Installed locally and invoked as separate programs; no part of them
  is linked into or shipped with this plugin.
