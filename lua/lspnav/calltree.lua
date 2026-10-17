local M = {}

local cfgmod = require("lspnav.calltree.config")

-- ---------------------------------------------------------------------------
-- lspnav.calltree
--
-- A side window showing the LSP call hierarchy of the symbol under the cursor:
-- who calls it (incoming, the default) or what it calls (outgoing). Children are
-- fetched lazily, one request per node the first time it is expanded, so a wide
-- hierarchy costs nothing until you look at it.
-- ---------------------------------------------------------------------------

---The live options, held by `lspnav.calltree.config`; the same table, so
---`lspnav.health` and the submodules all see one config.
---@type lspnav.calltree.Config
M.config = cfgmod.current

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

---@param opts? lspnav.calltree.Config
function M.setup(opts)
    _setup = true
    cfgmod.apply(opts)
end

return M
