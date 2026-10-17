---@class lspnav.util.floatwin
---
---A floating bar pinned across the bottom of the editor, for the side windows
---that read better over the code than in a split. It tracks the editor size on
---`:resize` and never takes focus when it is created.
local M = {}

local _BORDER = "rounded"
local _BORDER_SPAN = 2
local _TITLE_POS = "center"

-- Paint the float with Normal so the bar reads as part of the editor rather
-- than a popup; the tree's own highlights are buffer extmarks and still apply.
local _WINHL = "NormalFloat:Normal,FloatBorder:Normal,FloatTitle:Title"

--- Whether a status line occupies a row at the bottom of the editor.
---@return boolean
local function _has_statusline()
    local laststatus = vim.o.laststatus
    return laststatus ~= 0 and laststatus ~= 1
end

--- Editor rows the bar may use: everything `vim.o.lines` counts, less the
--- command line and the status line.
---@return integer
local function _usable_lines()
    local reserved = vim.o.cmdheight + (_has_statusline() and 1 or 0)
    return math.max(1, vim.o.lines - reserved)
end

---@param v number
---@param min number
---@param max number
---@return number
local function _clamp(v, min, max)
    return math.max(min, math.min(max, v))
end

--- The bar's content box for `height_ratio`, as `row, width, height`.
--- The border is outside these sizes; `row` is 0-based.
---@param height_ratio number?
---@return integer row
---@return integer width
---@return integer height
function M.layout(height_ratio)
    local usable = _usable_lines()
    -- A content width of `columns - 4` plus the two border columns spans all but
    -- one cell at either edge of the editor.
    local width = math.max(1, vim.o.columns - 4)
    local height = math.ceil(usable * _clamp(height_ratio or 0.25, 0.1, 0.9))
    height = math.min(math.max(1, height), math.max(1, usable - _BORDER_SPAN))
    return math.max(0, usable - height - _BORDER_SPAN), width, height
end

---@class lspnav.util.floatwin.Opts
---@field height_ratio number? share of the usable editor rows the bar spans (default 0.25)
---@field title string? shown centered in the border
---@field on_delete fun()? run when the window closes
---@field on_split? fun(bufnr: integer): integer?  open `bufnr` as a split and return its window

--- Open a bottom-bar float showing `buf`, without entering it. The caller may
--- focus it later, as `activate()` does for the side windows. With `on_split`,
--- `<C-q>` moves the buffer into a regular split and keeps its contents.
---@param buf integer
---@param opts lspnav.util.floatwin.Opts?
---@return integer winid
function M.create_float_win(buf, opts)
    opts = opts or {}
    local ratio = opts.height_ratio or 0.25
    local row, width, height = M.layout(ratio)

    ---@type vim.api.keyset.win_config
    local cfg = {
        relative   = "editor",
        style      = "minimal",
        row        = row,
        col        = 1,
        width      = width,
        height     = height,
        border     = _BORDER,
        title      = opts.title,
        title_pos  = opts.title and _TITLE_POS or nil,
        focusable  = true,
    }
    local win = vim.api.nvim_open_win(buf, false, cfg)

    local wo = vim.wo[win][0]
    wo.winhighlight = _WINHL
    -- "minimal" forces 'cursorline' off; take the opener's setting back.
    wo.cursorline = vim.wo.cursorline
    wo.wrap = false
    wo.winfixbuf = true
    -- A new window inherits its opener's options: opened from a scrollbound or
    -- cursorbound window, the bar would move along with it.
    wo.scrollbind = false
    wo.cursorbind = false

    vim.keymap.set("n", "<Esc>", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, desc = "Close window" })

    local group = vim.api.nvim_create_augroup("LspnavFloatWin" .. win, { clear = true })

    vim.api.nvim_create_autocmd("VimResized", {
        group = group,
        callback = function()
            vim.schedule(function()
                if not vim.api.nvim_win_is_valid(win) then return end
                local r, w, h = M.layout(ratio)
                vim.api.nvim_win_set_config(win, {
                    relative  = "editor",
                    row       = r,
                    col       = 1,
                    width     = w,
                    height    = h,
                    border    = _BORDER,
                    title     = opts.title,
                    title_pos = opts.title and _TITLE_POS or nil,
                })
            end)
        end,
    })

    -- A bottom bar is transient: once focus returns to a regular window (a jump
    -- out of the bar, a click in the code, another split) it has served its
    -- purpose. Other floats -- a hover, a second side window -- do not count.
    vim.api.nvim_create_autocmd("WinEnter", {
        group = group,
        callback = function()
            local cur = vim.api.nvim_get_current_win()
            if cur == win then return end
            if vim.api.nvim_win_get_config(cur).relative ~= "" then return end
            vim.schedule(function()
                if vim.api.nvim_win_is_valid(win) then
                    vim.api.nvim_win_close(win, true)
                end
            end)
        end,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(args)
            if tonumber(args.match) ~= win then return end
            pcall(vim.api.nvim_del_augroup_by_id, group)
            if opts.on_delete then opts.on_delete() end
        end,
    })

    if opts.on_split then
        vim.keymap.set("n", "<C-q>", function()
            local bufnr = vim.api.nvim_win_get_buf(win)
            local bufhidden = vim.bo[bufnr].bufhidden
            -- The scratch buffer wipes when its last window closes; hide it for
            -- the move so the tree it renders survives into the split.
            vim.bo[bufnr].bufhidden = "hide"
            pcall(vim.keymap.del, "n", "<C-q>", { buffer = bufnr })
            pcall(vim.keymap.del, "n", "<Esc>", { buffer = bufnr })
            vim.api.nvim_win_close(win, true)

            local newwin = opts.on_split(bufnr)
            if vim.api.nvim_buf_is_valid(bufnr) then
                vim.bo[bufnr].bufhidden = bufhidden
            end
            if newwin and vim.api.nvim_win_is_valid(newwin) then
                vim.api.nvim_set_current_win(newwin)
            end
        end, { buffer = buf, desc = "Open as split" })
    end

    return win
end

return M
