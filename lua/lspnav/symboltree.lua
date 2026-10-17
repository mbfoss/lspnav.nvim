local M = {}

local cfgmod = require("lspnav.symboltree.config")


---The live options, held by `lspnav.symboltree.config`; the same table, so
---`lspnav.health` and the submodules all see one config.
---@type lspnav.symboltree.Config
M.config = cfgmod.current

---Options that are valid but have no default, so `get_default_config()` has no
---key for them; `lspnav.health` would otherwise call them misspellings.
---@type table<string, true>
M.config_optional = {
    exclude_kinds = true,
}

local _setup = false

--- A fresh copy of the module defaults, as `setup()` starts from. Safe to mutate.
---@return table
function M.get_default_config()
    return cfgmod.defaults()
end

--- Whether `setup()` has been called for this module.
---@return boolean
function M.is_setup()
    return _setup
end

---@param opts? lspnav.symboltree.Config
function M.setup(opts)
    _setup = true
    cfgmod.apply(opts)
end

return M
