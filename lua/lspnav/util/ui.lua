local M = {}

local function _is_regular_win(winid)
    if not vim.api.nvim_win_is_valid(winid) then return false end
    local cfg = vim.api.nvim_win_get_config(winid)
    if cfg.relative ~= "" then return false end         -- skip popups
    if vim.wo[winid][0].winfixbuf then return false end -- skip fixed windows
    return true
end

---@param winid integer
---@param line? integer 1-based line number (nil = just open)
---@param col?  integer 0-based column (nil = column 0)
local function _safe_set_cursor_pos(winid, line, col)
    if not (line and type(line) == 'number' and line > 0) then return end
    if not vim.api.nvim_win_is_valid(winid) then return end
    local bufnr = vim.api.nvim_win_get_buf(winid)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    local maxline = vim.api.nvim_buf_line_count(bufnr)
    line = math.min(line, maxline)
    local line_length = #vim.api.nvim_buf_get_lines(bufnr, line - 1, line, true)[1]
    if col and type(col) == 'number' and col >= 0 then
        col = math.min(col, line_length)
    else
        col = 0
    end
    vim.api.nvim_win_set_cursor(winid, { line, col })
end

---@return number winid
local function _get_regular_window()
    local cur_win = vim.api.nvim_get_current_win()
    if _is_regular_win(cur_win) then
        return cur_win
    end

    local tabpage = vim.api.nvim_get_current_tabpage()
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        if winid ~= cur_win and _is_regular_win(winid) then
            return winid
        end
    end

    vim.cmd('vsplit')
    local newwin = vim.api.nvim_get_current_win()
    -- A split inherits window-local options from its parent, so splitting off a
    -- winfixbuf panel yields a winfixbuf window too; clear it so a file can load.
    vim.wo[newwin][0].winfixbuf = false
    return newwin
end


--- A scratch buffer; `buffer_options` override the defaults. `filetype` is set
--- last, after `on_delete` is hooked up, so `FileType` handlers see the final
--- options and a deletion from one still reaches `on_delete`.
---@param listed boolean
---@param buffer_options vim.bo?
---@param on_delete function?
function M.create_scratch_buffer(listed, buffer_options, on_delete)
    local buf = vim.api.nvim_create_buf(listed, true)
    local bo = { ---@type vim.bo
        buftype = "nofile",
        swapfile = false,
        modeline = false,
    }
    if not listed then
        bo.bufhidden = 'wipe'
    end
    if buffer_options then
        for k, v in pairs(buffer_options) do
            bo[k] = v
        end
    end
    local filetype = bo.filetype
    bo.filetype = nil
    for k, v in pairs(bo) do
        vim.bo[buf][k] = v
    end
    if on_delete then
        vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
            buffer = buf,
            once = true,
            callback = function(ev)
                on_delete()
            end,
        })
    end
    if filetype then
        vim.bo[buf].filetype = filetype
    end
    return buf
end

---@param bufnr integer
---@param line? integer 1-based line number (nil = just open)
---@param col?  integer 0-based column (nil = column 0)
---@param activate? boolean focus the target window (default true)
---@return number winid
function M.smart_open_buffer(bufnr, line, col, activate)
    local cur_win = vim.api.nvim_get_current_win()
    local winid = _get_regular_window()
    if activate ~= false then
        vim.api.nvim_set_current_win(winid)
    elseif vim.api.nvim_win_is_valid(cur_win) then
        -- `_get_regular_window` may have split one off and entered it.
        vim.api.nvim_set_current_win(cur_win)
    end
    vim.fn.win_execute(winid, "buffer " .. bufnr)
    _safe_set_cursor_pos(winid, line, col)
    return winid
end

--- Scroll the view of `winid` just enough to move its cursor out from under a
--- floating window that covers it. Only the view moves: no window is moved,
--- resized or refocused, and the cursor stays on the same buffer position. If no
--- amount of scrolling can clear the float, the view is left exactly as it was.
---@param winid integer window to reveal the cursor in
function M.reveal_cursor(winid)
    if not vim.api.nvim_win_is_valid(winid) then return end
    if vim.api.nvim_win_get_config(winid).relative ~= "" then return end

    local info = vim.fn.getwininfo(winid)[1]
    if not info then return end
    -- 0-based row of the first text line; above it sit the window's winbar (if
    -- any) and whatever the layout puts there.
    local text_top = info.winrow - 1 + info.winbar

    -- Screen row the cursor is on now, or 0 when it is not displayed.
    local line = vim.api.nvim_win_call(winid, vim.fn.winline)
    if line == 0 then return end
    local row = text_top + line - 1

    -- The screen rows floats cover, border included: half-open [top, bot)
    -- pairs. A border lies outside the position and height the config reports,
    -- so widen each float by it.
    local covers = {}
    for _, float in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local cfg = vim.api.nvim_win_get_config(float)
        if cfg.relative ~= "" and not cfg.hide and not cfg.external then
            local b   = cfg.border
            local pad = b and b ~= "none" and b ~= "shadow" and 1 or 0
            local top = vim.api.nvim_win_get_position(float)[1] - pad
            covers[#covers + 1] = { top, top + vim.api.nvim_win_get_height(float) + 2 * pad }
        end
    end

    -- Step above whichever float covers the target row until none does: floats
    -- can be stacked, so clearing the one over the cursor is not always enough.
    local target = row
    local moved  = true
    while moved do
        moved = false
        for _, cover in ipairs(covers) do
            if target >= cover[1] and target < cover[2] then
                target = cover[1] - 1
                moved  = true
            end
        end
    end
    if target == row then return end -- nothing covers the cursor
    if target < text_top then return end -- the whole text area is behind the floats

    -- `winline()` is 1-based from the text area, so the cursor has to end at or
    -- above `want`. Scrolling only moves the cursor line up the screen, so
    -- bisect for the smallest topline -- the least scrolling -- that clears the
    -- float. A topline past the cursor line would hide it, and winrestview
    -- clamps there. One window switch covers every probe.
    vim.api.nvim_win_call(winid, function()
        local original = vim.fn.winsaveview()
        local want     = target - text_top + 1

        vim.fn.winrestview({ topline = original.lnum })
        if vim.fn.winline() > want then
            -- 'scrolloff' holds the cursor too low even with its line at the
            -- top: no amount of scrolling can clear the float.
            vim.fn.winrestview(original)
            return
        end

        local lo, hi = original.topline, original.lnum
        while lo < hi do
            local mid = math.floor((lo + hi) / 2)
            vim.fn.winrestview({ topline = mid })
            if vim.fn.winline() <= want then
                hi = mid
            else
                lo = mid + 1
            end
        end
        vim.fn.winrestview({ topline = lo })
    end)
end

return M
