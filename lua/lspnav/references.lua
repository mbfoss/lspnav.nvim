local M = {}

local cfgmod = require("lspnav.references.config")

-- ---------------------------------------------------------------------------
-- lspnav.references
--
-- A side window listing every reference to the symbol under the cursor, grouped
-- by the file each one sits in. The server answers in one reply, so the whole
-- list is built at once and folding only hides what is already there.
-- ---------------------------------------------------------------------------

---The live options, held by `lspnav.references.config`; the same table, so
---`lspnav.health` and the submodules all see one config.
---@type lspnav.references.Config
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

---@param opts? lspnav.references.Config
function M.setup(opts)
    _setup = true
    cfgmod.apply(opts)
end

return M
