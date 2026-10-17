-- lspnav.nvim
--
-- `require("lspnav").setup({...})` configures any combination of the features
-- from one table:
--
--   require("lspnav").setup({
--     motions    = { function_kinds = { 6, 9, 12 } },
--     symboltree = { width_ratio = 0.3 },
--   })
--
-- Nothing is loaded until an option is set or a feature is used.

local M = {}

--- The table accepted by `require("lspnav").setup()`
---@class lspnav.Config
---@field motions lspnav.motions.Config?
---@field symboltree lspnav.symboltree.Config?
---@field calltree lspnav.calltree.Config?
---@field references lspnav.references.Config?

--- Options `setup()` accepts.
---@type table<string, true>
local _OPTIONS = {
  motions = true,
  symboltree = true,
  calltree = true,
  references = true,
}

--- Configure lspnav from a single table. Each key names a feature and its value
--- is that feature's options table; omitted features keep their defaults.
---@param opts? lspnav.Config
function M.setup(opts)
  opts = opts or {}

  for name, value in pairs(opts) do
    if not _OPTIONS[name] then
      vim.notify(("lspnav.setup: unknown option %q"):format(name), vim.log.levels.WARN)
    elseif type(value) ~= "table" then
      vim.notify(("lspnav.setup: %q expects an options table"):format(name), vim.log.levels.WARN)
    end
  end

  if type(opts.motions) == "table" then
    require("lspnav.motions").setup(opts.motions)
  end
  if type(opts.symboltree) == "table" then
    require("lspnav.symboltree").setup(opts.symboltree)
  end
  if type(opts.calltree) == "table" then
    require("lspnav.calltree").setup(opts.calltree)
  end
  if type(opts.references) == "table" then
    require("lspnav.references").setup(opts.references)
  end
end

-- ---------------------------------------------------------------------------
-- :Lspnav
--
-- The command itself is registered in `plugin/lspnav.lua` without loading this
-- module. Its first argument is a motion action (`next_function`, ...) or a
-- feature whose own subcommand follows: `:Lspnav symboltree open`.

--- Motion subcommands, dispatched to `lspnav.motions`.
---@type string[]
local _MOTION_COMMANDS = {
  "next_function",
  "prev_function",
  "next_type",
  "prev_type",
}

--- All subcommands, in completion order.
---@type string[]
local _SUBCOMMANDS = vim.list_extend(vim.list_extend({}, _MOTION_COMMANDS), {
  "symboltree",
  "calltree",
  "references",
})

---@type table<string, true>
local _MOTION_COMMAND = {}
for _, name in ipairs(_MOTION_COMMANDS) do _MOTION_COMMAND[name] = true end

---@type table<string, true>
local _KNOWN_SUBCOMMAND = {}
for _, name in ipairs(_SUBCOMMANDS) do _KNOWN_SUBCOMMAND[name] = true end

--- Run `:Lspnav`. A motion action calls `lspnav.motions` directly; any other
--- feature is loaded on first use and set up with its defaults when `setup()`
--- has not run, so a command works from a bare install.
---@param args string[]
function M.run(args)
  local name = args[1]
  if name == nil or name == "" then
    vim.notify(
      "lspnav: missing subcommand (expected one of: " .. table.concat(_SUBCOMMANDS, ", ") .. ")",
      vim.log.levels.ERROR
    )
    return
  end
  if not _KNOWN_SUBCOMMAND[name] then
    vim.notify(("lspnav: unknown subcommand %q"):format(name), vim.log.levels.ERROR)
    return
  end

  if _MOTION_COMMAND[name] then
    local count = args[2] and tonumber(args[2])
    if args[2] ~= nil and (not count or count < 1 or count ~= math.floor(count)) then
      vim.notify(
        ("lspnav: %s expects a positive count, got %q"):format(name, args[2]),
        vim.log.levels.ERROR
      )
      return
    end
    require("lspnav.motions")[name](nil, count)
    return
  end

  local feature = require("lspnav." .. name)
  if type(feature.is_setup) == "function" and not feature.is_setup() then
    feature.setup({})
  end
  require("lspnav." .. name .. ".command").run(vim.list_slice(args, 2))
end

--- `:Lspnav`'s completion, as an `lspnav.util.usercmd.subcommand`. Only the
--- command tables are required, so completing does not activate anything.
---@param _cmd string
---@param rest string[]
---@param _lead string
---@return string[]
function M.complete(_cmd, rest, _lead)
  if #rest == 0 then
    return vim.deepcopy(_SUBCOMMANDS)
  end
  local name = rest[1]
  if not _KNOWN_SUBCOMMAND[name] then
    return {}
  end
  if _MOTION_COMMAND[name] then
    return {}
  end
  return require("lspnav." .. name .. ".command").get_subcommands(vim.list_slice(rest, 2))
end

return M
