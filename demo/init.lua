-- Minimal init for the demo scene. nvim-demo starts Neovim with --clean and a
-- custom -u, which skips default filetype detection; turn it on for clangd.
vim.cmd("filetype on")

vim.o.number = true
vim.o.signcolumn = "no"
vim.o.termguicolors = true
vim.o.background = "dark"
vim.cmd.colorscheme("catppuccin")
vim.o.swapfile = false
vim.o.shadafile = "NONE"
vim.o.shortmess = vim.o.shortmess .. "I"

-- nvim-demo puts its own root on 'runtimepath', so this works before the
-- plugin is added below.
require("nvim_demo").setup()

local demo_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.opt.rtp:append(demo_dir .. "/..")

-- A little wider than the default so symbol names and details are readable.
require("lspnav").setup({
    symboltree = { width_ratio = 0.26 },
})

-- clangd is not guaranteed to be on PATH. Prefer $CLANGD, then PATH, then the
-- usual install locations.
local function find_clangd()
    local candidates = {}
    local function add(path)
        if path and path ~= "" then
            table.insert(candidates, path)
        end
    end

    add(vim.env.CLANGD)
    add(vim.fn.exepath("clangd"))
    add("/usr/bin/clangd")
    add("/usr/local/bin/clangd")
    add("/opt/homebrew/bin/clangd")
    add("/Library/Developer/CommandLineTools/usr/bin/clangd")

    for _, path in ipairs(candidates) do
        if vim.fn.executable(path) == 1 then
            return path
        end
    end
end

local clangd = find_clangd()

-- Configure the client and open the fixture after startup. vim.lsp.enable()
-- does not take effect from inside the vimrc, and autocmds are not nested by
-- default, so :edit must be issued from a nested VimEnter callback to fire
-- filetype detection and the LSP attach autocmd.
vim.api.nvim_create_autocmd("VimEnter", {
    nested = true,
    callback = function()
        if clangd then
            vim.lsp.config("clangd", {
                cmd = { clangd, "--background-index=false" },
                root_dir = demo_dir,
            })
            vim.lsp.enable("clangd")
        end

        vim.cmd.edit(demo_dir .. "/sample.c")
        if vim.bo.filetype == "" then
            vim.bo.filetype = "c"
        end
    end,
})
