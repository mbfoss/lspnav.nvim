---@brief The calltree options. A leaf module, so the window and tree code can
---read the live config without requiring `lspnav.calltree` itself.

local cfgutil = require("lspnav.util.config")

local M = {}

---@class lspnav.calltree.Config
---@field display "float"|"split"?  "float" for a bottom bar, "split" for a split window
---@field width_ratio number?   split only: fraction of the editor width (left/right)
---@field height_ratio number?  fraction of the editor height (float and top/bottom split)
---@field position "top"|"bottom"|"left"|"right"?  split only: side the window opens on
---@field direction lspnav.calltree.Direction?  which way to walk by default
---@field show_detail boolean?  show the server-provided detail text
---@field auto_expand_root boolean?  expand the root as soon as it resolves
---@field indent_guides boolean?  draw vertical indent guides

---@type lspnav.calltree.Config
local _defaults = {
    display          = "float",
    width_ratio      = 0.2,
    height_ratio     = 0.25,
    position         = "bottom",
    direction        = "incoming",
    show_detail      = true,
    auto_expand_root = true,
    indent_guides    = false,
}

---The live options. Always this same table, so it is safe to capture at a
---module's top.
---@type lspnav.calltree.Config
M.current = vim.deepcopy(_defaults)

---A fresh copy of the defaults, as `apply()` starts from. Safe to mutate.
---@return lspnav.calltree.Config
function M.defaults()
    return vim.deepcopy(_defaults)
end

---@param opts? lspnav.calltree.Config
function M.apply(opts)
    cfgutil.apply(M.current, _defaults, opts)
end

return M
