local M = {}

local function _tree()
    return require("lspnav.symboltree.tree")
end

---@param rest string[]
---@return string[]
function M.get_subcommands(rest)
    if #rest == 0 then
        return { "open", "close", "toggle" }
    end
    return {}
end

---@param args string[]
function M.run(args)
    local command = args[1]
    if command == nil or command == "" then
        _tree().activate()
    elseif command == "toggle" then
        _tree().toggle()
    elseif command == "open" then
        _tree().open()
    elseif command == "close" then
        _tree().close()
    else
        vim.notify("Invalid Lspnav symboltree subcommand: " .. tostring(command))
    end
end

return M
