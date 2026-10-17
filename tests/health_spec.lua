local lspnav = require("lspnav")
local health = require("lspnav.health")
local motions = require("lspnav.motions")

--- Run `health.check()` with `vim.health` stubbed, returning the reported
--- entries as `{ level, message }` pairs.
---@return table[]
local function capture()
  local entries = {}
  local saved = {}
  -- `lspnav.health` holds a reference to the `vim.health` table, so the
  -- functions on it are what must be swapped, not the table itself.
  for _, level in ipairs({ "start", "ok", "info", "warn", "error" }) do
    saved[level] = vim.health[level]
    vim.health[level] = function(msg)
      table.insert(entries, { level = level, message = msg })
    end
  end
  local ok, err = pcall(health.check)
  for level, fn in pairs(saved) do
    vim.health[level] = fn
  end
  assert(ok, err)
  return entries
end

--- All messages reported at `level`, joined.
---@param entries table[]
---@param level string
---@return string
local function messages(entries, level)
  local out = {}
  for _, entry in ipairs(entries) do
    if entry.level == level then table.insert(out, entry.message) end
  end
  return table.concat(out, "\n")
end

--- The messages reported under the `section` heading, joined.
---@param entries table[]
---@param section string
---@return string?
local function section(entries, section_name)
  local out
  for _, entry in ipairs(entries) do
    if entry.level == "start" then
      if out then return table.concat(out, "\n") end
      out = entry.message == section_name and {} or nil
    elseif out then
      table.insert(out, entry.message)
    end
  end
  return out and table.concat(out, "\n")
end

describe("lspnav.health", function()
  after_each(function()
    package.loaded["lspnav.motions"] = motions
    motions.setup({})
  end)

  it("gives a module at its defaults no section", function()
    lspnav.setup({ motions = {} })
    assert.is_nil(section(capture(), "lspnav.motions: configuration"))
  end)

  it("sections a modified module with only the changed options", function()
    lspnav.setup({ motions = { type_kinds = { 5 } } })
    local reported = section(capture(), "lspnav.motions: configuration")
    assert.matches("type_kinds = { 5 }", reported)
    assert.is_nil(reported:match("function_kinds"))
  end)

  it("flags an option the module does not define", function()
    lspnav.setup({ motions = { type_kind = { 5 } } })
    assert.matches("type_kind", messages(capture(), "warn"))
  end)
end)
