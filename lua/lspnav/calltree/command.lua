local M = {}

local function _tree()
    return require("lspnav.calltree.tree")
end

---@param rest string[]
---@return string[]
function M.get_subcommands(rest)
    if #rest == 0 then
        return { "open", "incoming", "outgoing", "swap", "refresh", "close", "toggle" }
    end
    return {}
end

---@param args string[]
function M.run(args)
    local command = args[1]
    -- No argument re-targets the symbol under the cursor rather than
    -- toggling, so repeating the command follows you around the code, and it
    -- moves focus into the window so the tree is navigable at once.
    if command == nil or command == "" then
        _tree().activate()
    elseif command == "open" then
        _tree().open()
    elseif command == "toggle" then
        _tree().toggle()
    elseif command == "incoming" then
        _tree().activate("incoming")
    elseif command == "outgoing" then
        _tree().activate("outgoing")
    elseif command == "swap" then
        _tree().swap_direction()
    elseif command == "refresh" then
        _tree().refresh()
    elseif command == "close" then
        _tree().close()
    else
        vim.notify("Invalid Lspnav calltree subcommand: " .. tostring(command))
    end
end

return M
