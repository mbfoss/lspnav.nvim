local lspnav = require("lspnav")
local motions = require("lspnav.motions")

describe("lspnav.setup", function()
  after_each(function()
    motions.setup({})
  end)

  it("warns about an unknown option", function()
    local messages = {}
    local notify = vim.notify
    vim.notify = function(msg) messages[#messages + 1] = msg end
    local ok, err = pcall(lspnav.setup, { bogus = {} })
    vim.notify = notify
    assert.is_true(ok, err)
    assert.equals(1, #messages)
    assert.matches("unknown option", messages[1])
  end)

  it("warns when a value is not an options table", function()
    local messages = {}
    local notify = vim.notify
    vim.notify = function(msg) messages[#messages + 1] = msg end
    local ok, err = pcall(lspnav.setup, { motions = true })
    vim.notify = notify
    assert.is_true(ok, err)
    assert.equals(1, #messages)
    assert.matches("options table", messages[1])
  end)

  it("delegates a table value as feature opts", function()
    lspnav.setup({ motions = { type_kinds = { 5 } } })
    assert.same({ 5 }, motions.config.type_kinds)
  end)

  it("leaves unmentioned features untouched", function()
    package.loaded["lspnav.motions"] = nil
    lspnav.setup({})
    assert.is_nil(package.loaded["lspnav.motions"])
  end)
end)

describe("lspnav command", function()
  it("completes the subcommands at the top level", function()
    assert.same({
      "next_function", "prev_function", "next_type", "prev_type",
      "symboltree", "calltree", "references",
    }, lspnav.complete("", {}, ""))
  end)

  it("offers no completion after a motion subcommand", function()
    assert.same({}, lspnav.complete("", { "next_function" }, ""))
  end)

  it("dispatches a motion subcommand with an optional count", function()
    local calls = {}
    local real = package.loaded["lspnav.motions"]
    package.loaded["lspnav.motions"] = setmetatable({}, {
      __index = function(_, action)
        return function(_, count) calls[#calls + 1] = { action = action, count = count } end
      end,
    })
    lspnav.run({ "next_function", "3" })
    lspnav.run({ "prev_type" })
    package.loaded["lspnav.motions"] = real
    assert.same({ action = "next_function", count = 3 }, calls[1])
    assert.same({ action = "prev_type", count = nil }, calls[2])
  end)

  it("rejects a motion subcommand count that is not positive", function()
    local messages = {}
    local notify = vim.notify
    vim.notify = function(msg) messages[#messages + 1] = msg end
    local ok, err = pcall(lspnav.run, { "next_function", "0" })
    vim.notify = notify
    assert.is_true(ok, err)
    assert.equals(1, #messages)
    assert.matches("positive count", messages[1])
  end)

  it("delegates completion to the named feature", function()
    assert.same({ "open", "close", "toggle" }, lspnav.complete("", { "symboltree" }, ""))
    assert.same({ "open", "refresh", "close", "toggle" }, lspnav.complete("", { "references" }, ""))
  end)

  it("offers nothing after an unknown subcommand", function()
    assert.same({}, lspnav.complete("", { "bogus" }, ""))
  end)

  it("notifies on a missing or unknown subcommand", function()
    local messages = {}
    local notify = vim.notify
    vim.notify = function(msg) messages[#messages + 1] = msg end
    local ok, err = pcall(function()
      lspnav.run({})
      lspnav.run({ "bogus" })
    end)
    vim.notify = notify
    assert.is_true(ok, err)
    assert.equals(2, #messages)
  end)
end)
