local M = {}

local function _tree()
    return require("lspnav.references.tree")
end

---@param rest string[]
---@return string[]
function M.get_subcommands(rest)
    if #rest == 0 then
        return { "open", "refresh", "close", "toggle" }
    end
    return {}
end

---@param args string[]
function M.run(args)
    local command = args[1]
    -- No argument re-targets the symbol under the cursor rather than
    -- toggling, so repeating the command follows you around the code, and it
    -- moves focus into the window so the list is navigable at once.
    if command == nil or command == "" then
        _tree().activate()
    elseif command == "open" then
        _tree().open()
    elseif command == "toggle" then
        _tree().toggle()
    elseif command == "refresh" then
        _tree().refresh()
    elseif command == "close" then
        _tree().close()
    else
        vim.notify("Invalid Lspnav references subcommand: " .. tostring(command))
    end
end

return M
