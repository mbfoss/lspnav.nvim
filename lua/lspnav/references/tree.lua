local M = {}

local config   = require("lspnav.references.config").current
local fixedwin = require("lspnav.util.fixedwin")
local floatwin = require("lspnav.util.floatwin")

local _KEY_MARKER = "LspnavReferencesWin"

local _tree ---@type lspnav.References?

---@return number?
local function _get_win()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())) do
        local ok, val = pcall(function() return vim.w[win][_KEY_MARKER] end)
        if ok and val == true then return win end
    end
    return nil
end

-- Set a window-local option without leaking it into nvim's hidden global default
-- (see lspnav.util.fixedwin for the gotcha this avoids).
---@param win integer
---@param opt string
---@param val any
local function _setlocal(win, opt, val)
    vim.api.nvim_set_option_value(opt, val, { win = win, scope = "local" })
end

---@return lspnav.References
local function _get_tree()
    if not _tree then
        local References = require("lspnav.references.References")
        _tree = References:new({
            include_declaration = config.include_declaration,
            show_line           = config.show_line,
            view                = config.view,
            auto_expand         = config.auto_expand,
            indent_guides       = config.indent_guides,
        })
    end
    return _tree
end

---@param win integer
local function _configure_win(win)
    vim.w[win][_KEY_MARKER] = true
    _setlocal(win, "wrap", false)
    _setlocal(win, "spell", false)
    _setlocal(win, "winfixbuf", true)
end

--- Open `bufnr` in a split pinned to a ratio of the editor size: width for
--- left/right, height for top/bottom. fixedwin re-pins the ratio across
--- layout/editor changes; persisting it keeps the user's chosen size across
--- reopenings.
---@param bufnr integer
---@param enter boolean?
---@return integer win
local function _open_split(bufnr, enter)
    local position = config.position or "bottom"
    local vertical = position == "left" or position == "right"
    local pos = (position == "left" or position == "top") and "topleft" or "botright"
    local win = fixedwin.create_fixed_win(bufnr, {
        axis  = vertical and "width" or "height",
        ratio = vertical and (config.width_ratio or 0.2) or (config.height_ratio or 0.25),
        pos   = pos,
        enter = enter,
        on_delete = function(ratio)
            if vertical then
                config.width_ratio = ratio
            else
                config.height_ratio = ratio
            end
        end,
    })
    return win
end

---@return integer? win
local function _open_win()
    local existing = _get_win()
    if existing then return existing end

    local tree = _get_tree()
    tree:create_buffer()
    local bufnr = tree:get_bufnr()
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return nil
    end

    local win
    if config.display == "split" then
        win = _open_split(bufnr)
    else
        win = floatwin.create_float_win(bufnr, {
            height_ratio = config.height_ratio,
            title        = " References ",
            on_split = function()
                local newwin = _open_split(bufnr, true)
                _configure_win(newwin)
                return newwin
            end,
        })
    end

    _configure_win(win)

    local bufname = "lspnav://" .. bufnr .. "/references"
    vim.api.nvim_buf_set_name(bufnr, bufname)

    return win
end

--- Open the window on the symbol under the cursor, re-querying an already-open
--- one. Must be called from the source window, since that cursor is what names
--- the symbol; called from the window itself there is nothing to re-query.
function M.open()
    local source_buf = vim.api.nvim_get_current_buf()
    local source_win = vim.api.nvim_get_current_win()

    if source_win == _get_win() then return end

    if not _open_win() then return end

    _get_tree():show_from_cursor(source_buf, source_win)
end

--- Open the window as `open()` does, then move focus into it so the references
--- can be navigated straight away.
function M.activate()
    M.open()
    local win = _get_win()
    if win and vim.api.nvim_get_current_win() ~= win then
        vim.api.nvim_set_current_win(win)
    end
end

function M.close()
    local win = _get_win()
    if win then
        vim.api.nvim_win_close(win, false)
    end
end

--- Close the window if it is open, otherwise open it on the symbol under the
--- cursor.
function M.toggle()
    if _get_win() then
        M.close()
    else
        M.open()
    end
end

function M.refresh()
    if not _get_win() then return end
    _get_tree():refresh()
end

function M.is_visible()
    return _get_win() ~= nil
end

return M
