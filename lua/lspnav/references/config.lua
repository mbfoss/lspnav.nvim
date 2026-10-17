---@brief The references options. A leaf module, so the window and tree code can
---read the live config without requiring `lspnav.references` itself.

local cfgutil = require("lspnav.util.config")

local M = {}

---@class lspnav.references.Config
---@field display "float"|"split"?  "float" for a bottom bar, "split" for a split window
---@field width_ratio number?   split only: fraction of the editor width (left/right)
---@field height_ratio number?  fraction of the editor height (float and top/bottom split)
---@field position "top"|"bottom"|"left"|"right"?  split only: side the window opens on
---@field include_declaration boolean?  count the declaration itself as a reference
---@field show_line boolean?  show the source line each reference sits on
---@field view "tree"|"flat"?  tree compacts folder chains, flat lists file headings
---@field auto_expand boolean?  expand every folder and file as soon as it resolves
---@field indent_guides boolean?  draw vertical indent guides

---@type lspnav.references.Config
local _defaults = {
    display             = "float",
    width_ratio         = 0.2,
    height_ratio        = 0.25,
    position            = "bottom",
    include_declaration = true,
    show_line           = true,
    view                = "tree",
    auto_expand         = true,
    indent_guides       = false,
}

---The live options. Always this same table, so it is safe to capture at a
---module's top.
---@type lspnav.references.Config
M.current = vim.deepcopy(_defaults)

---A fresh copy of the defaults, as `apply()` starts from. Safe to mutate.
---@return lspnav.references.Config
function M.defaults()
    return vim.deepcopy(_defaults)
end

---@param opts? lspnav.references.Config
function M.apply(opts)
    cfgutil.apply(M.current, _defaults, opts)
end

return M
