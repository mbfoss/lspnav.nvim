---@brief Health check for lspnav.nvim, run with `:checkhealth lspnav`.

local M = {}

local _h = vim.health

--- Collect the options whose value differs from the default, as flat paths
--- (`enabled`, `builtin.marks`) with the value now in force. Lists are compared
--- whole: a `triggers` is one option, not one option per trigger.
---@param current table
---@param defaults table
---@param prefix string path of the enclosing table, "" at the top level
---@param out table[]
---@param optional table<string, true>  paths that are valid with no default
---@return table[]
local function _diff_config(current, defaults, prefix, out, optional)
  for key, value in pairs(current) do
    local path = prefix .. tostring(key)
    local default = defaults[key]
    if type(value) == "table" and type(default) == "table" and not vim.islist(value) then
      _diff_config(value, default, path .. ".", out, optional)
    elseif not vim.deep_equal(value, default) then
      table.insert(out, {
        path = path,
        -- one line: a health entry is a bullet, not a pretty-printed dump.
        value = vim.inspect(value, { newline = " ", indent = "" }),
        -- `setup()` merges opts wholesale, so a misspelled option is kept
        -- silently; only a key neither the defaults nor `config_optional`
        -- mention can be one.
        unknown = default == nil and not optional[path],
      })
    end
  end
  return out
end

--- The options a configured module holds that differ from its defaults, sorted by
--- path. Empty for a module that takes no options.
---@param mod table
---@return table[]
local function _changed_options(mod)
  if type(mod.get_default_config) ~= "function" or type(mod.config) ~= "table" then
    return {}
  end
  local diffs = _diff_config(mod.config, mod.get_default_config(), "", {}, mod.config_optional or {})
  table.sort(diffs, function(a, b) return a.path < b.path end)
  return diffs
end

local function _check_requirements()
  if vim.fn.has("nvim-0.11") ~= 1 then
    _h.start("lspnav: requirements")
    _h.error("lspnav.nvim requires Neovim >= 0.11")
  end
end

--- One section per configured module whose options were changed, listing only
--- what differs. Modules left at their defaults are omitted; an unconfigured
--- module is not set up, and an unloaded one is not in `package.loaded`.
local function _check_configs()
  local configured = {}
  for key, mod in pairs(package.loaded) do
    local name = key:match("^lspnav%.([^.]+)$")
    if name and name ~= "health" and type(mod) == "table"
        and (type(mod.is_setup) ~= "function" or mod.is_setup()) then
      configured[#configured + 1] = { name = name, mod = mod }
    end
  end
  table.sort(configured, function(a, b) return a.name < b.name end)

  for _, entry in ipairs(configured) do
    local mod = entry.mod
    local diffs = _changed_options(mod)
    if #diffs > 0 then
      _h.start("lspnav." .. entry.name .. ": configuration")
      for _, diff in ipairs(diffs) do
        _h.info(("%s = %s"):format(diff.path, diff.value))
      end
      for _, diff in ipairs(diffs) do
        if diff.unknown then
          _h.warn(("`%s` is not an option this module defines"):format(diff.path), {
            "check its spelling against the module's default config",
          })
        end
      end
    end
  end
end

function M.check()
  _check_requirements()
  _check_configs()
end

return M
