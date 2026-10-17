local M = {}

local config   = require("lspnav.calltree.config").current
local fixedwin = require("lspnav.util.fixedwin")
local floatwin = require("lspnav.util.floatwin")

local _KEY_MARKER = "LspnavCallTreeWin"

local _tree ---@type lspnav.CallTree?

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

---@return lspnav.CallTree
local function _get_tree()
    if not _tree then
        local CallTree = require("lspnav.calltree.CallTree")
        _tree = CallTree:new({
            direction        = config.direction,
            show_detail      = config.show_detail,
            auto_expand_root = config.auto_expand_root,
            indent_guides    = config.indent_guides,
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
            title        = " Call Hierarchy ",
            on_split = function()
                local newwin = _open_split(bufnr, true)
                _configure_win(newwin)
                return newwin
            end,
        })
    end

    _configure_win(win)

    local bufname = "lspnav://" .. bufnr .. "/call-tree"
    vim.api.nvim_buf_set_name(bufnr, bufname)

    return win
end

--- Open the tree on the symbol under the cursor, re-rooting an already-open one.
--- Must be called from the source window, since that cursor is what names the
--- symbol; called from the tree itself it only applies `direction`, leaving the
--- root alone.
---@param direction lspnav.calltree.Direction? overrides the configured direction
function M.open(direction)
    local source_buf = vim.api.nvim_get_current_buf()
    local source_win = vim.api.nvim_get_current_win()

    if source_win == _get_win() then
        if direction then _get_tree():set_direction(direction) end
        return
    end

    if not _open_win() then return end

    _get_tree():show_from_cursor(source_buf, source_win, direction)
end

--- Open the tree as `open()` does, then move focus into its window so the tree
--- can be navigated straight away.
---@param direction lspnav.calltree.Direction? overrides the configured direction
function M.activate(direction)
    M.open(direction)
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

--- Close the tree if it is open, otherwise open it on the symbol under the
--- cursor.
function M.toggle()
    if _get_win() then
        M.close()
    else
        M.open()
    end
end

--- Swap between incoming and outgoing calls, keeping the current root. Opens the
--- tree on the symbol under the cursor if it is not showing yet.
function M.swap_direction()
    if not _get_win() then
        M.open(_get_tree():get_direction() == "incoming" and "outgoing" or "incoming")
        return
    end
    _get_tree():swap_direction()
end

function M.refresh()
    if not _get_win() then return end
    _get_tree():refresh()
end

function M.is_visible()
    return _get_win() ~= nil
end

return M
