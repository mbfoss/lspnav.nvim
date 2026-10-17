if vim.fn.has("nvim-0.11") ~= 1 then
    error("lspnav.nvim requires Neovim >= 0.11")
end

-- `:Lspnav` is registered without requiring any Lua: both callbacks pull in
-- what they need on first use, and cache it in these locals.
local usercmd ---@type table?
local lspnav ---@type table?

---@return table
local function _usercmd()
    usercmd = usercmd or require("lspnav.util.usercmd")
    return usercmd
end

---@return table
local function _lspnav()
    lspnav = lspnav or require("lspnav")
    return lspnav
end

vim.api.nvim_create_user_command("Lspnav", function(opts)
    -- nargs="*" always yields fargs; the fallback is only to satisfy its
    -- optional type. Errors become notifications, not stack traces.
    local ok, err = pcall(_lspnav().run, opts.fargs or {}, opts)
    if not ok then
        vim.notify(
            "[lspnav] " .. opts.name .. " command error\n" .. tostring(err),
            vim.log.levels.ERROR
        )
    end
end, {
    nargs = "*",
    desc = "LSP navigation: motions, symbol tree, call hierarchy and references",
    complete = function(arg_lead, cmd_line, _)
        return _usercmd().complete(arg_lead, cmd_line,
            function(cmd, rest, lead)
                return _lspnav().complete(cmd, rest, lead)
            end)
    end,
})
