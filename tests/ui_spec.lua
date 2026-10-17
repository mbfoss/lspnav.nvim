local floatwin = require("lspnav.util.floatwin")
local ui       = require("lspnav.util.ui")

---@param n integer
---@param wrap boolean?
---@return string[]
local function lines(n, wrap)
    local result = {}
    for i = 1, n do
        result[i] = wrap and ("line " .. i .. " " .. string.rep("x", 300)) or ("line " .. i)
    end
    return result
end

--- 0-based screen row of the window's first text line.
---@param win integer
---@return integer
local function text_top(win)
    local info = vim.fn.getwininfo(win)[1]
    return info.winrow - 1 + info.winbar
end

--- 0-based screen row the cursor is on.
---@param win integer
---@return integer
local function cursor_row(win)
    local line = vim.api.nvim_win_call(win, function() return vim.fn.winline() end)
    return text_top(win) + line - 1
end

--- The screen rows `win` covers, border included: 0-based, `bot` exclusive.
---@param win integer
---@return integer top
---@return integer bot
local function cover(win)
    local pos    = vim.api.nvim_win_get_position(win)
    local cfg    = vim.api.nvim_win_get_config(win)
    local border = cfg.border ~= nil and cfg.border ~= "none" and cfg.border ~= "shadow"
    local pad    = border and 1 or 0
    return pos[1] - pad, pos[1] + vim.api.nvim_win_get_height(win) + pad
end

--- Put `win`'s cursor on `lnum`, scrolled to the top of the buffer.
---@param win integer
---@param lnum integer
local function at_top(win, lnum)
    vim.api.nvim_win_set_cursor(win, { lnum, 0 })
    vim.api.nvim_win_call(win, function() vim.fn.winrestview({ topline = 1, leftcol = 0 }) end)
end

describe("util.ui.reveal_cursor", function()
    local buf, float, upper, upper_buf

    after_each(function()
        for _, win in ipairs({ float, upper }) do
            if win and vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_close(win, true)
            end
        end
        for _, b in ipairs({ buf, upper_buf }) do
            if b and vim.api.nvim_buf_is_valid(b) then
                vim.api.nvim_buf_delete(b, { force = true })
            end
        end
        vim.cmd("only")
        vim.wo.wrap = false
        buf, float, upper, upper_buf = nil, nil, nil, nil
    end)

    --- Open the bottom bar over the editor, with `height_ratio` 0.25.
    ---@return integer top 0-based screen row of its top border
    local function open_bar()
        buf = vim.api.nvim_create_buf(false, true)
        float = floatwin.create_float_win(buf, { height_ratio = 0.25 })
        return floatwin.layout(0.25) - 1
    end

    it("scrolls the view so the cursor is not hidden behind a float", function()
        vim.cmd("only")
        local target = vim.api.nvim_get_current_win()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines(200))
        local bar_top = open_bar()

        at_top(target, 18)
        assert.is_true(cursor_row(target) >= bar_top)

        ui.reveal_cursor(target)

        assert.is_true(cursor_row(target) < bar_top)
        assert.same({ 18, 0 }, vim.api.nvim_win_get_cursor(target))
    end)

    it("scrolls screen lines, not buffer lines, when text wraps", function()
        vim.cmd("only")
        local target = vim.api.nvim_get_current_win()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines(200, true))
        vim.wo[target].wrap = true
        local bar_top = open_bar()

        at_top(target, 6)
        assert.is_true(cursor_row(target) >= bar_top)

        ui.reveal_cursor(target)

        assert.is_true(cursor_row(target) < bar_top)
        assert.same({ 6, 0 }, vim.api.nvim_win_get_cursor(target))
    end)

    it("leaves the view alone when the window sits entirely behind the float", function()
        vim.cmd("only")
        local under = vim.api.nvim_get_current_win()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines(100))
        vim.cmd("split")
        vim.api.nvim_win_set_height(under, 2)
        local bar_top = open_bar()

        assert.is_true(text_top(under) > bar_top)
        vim.api.nvim_win_set_cursor(under, { 1, 0 })
        local before = vim.api.nvim_win_call(under, vim.fn.winsaveview)

        ui.reveal_cursor(under)

        assert.same(before, vim.api.nvim_win_call(under, vim.fn.winsaveview))
    end)

    it("leaves the view alone when no float covers the cursor", function()
        vim.cmd("only")
        local target = vim.api.nvim_get_current_win()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines(200))
        local bar_top = open_bar()

        at_top(target, 3)
        assert.is_true(cursor_row(target) < bar_top)
        local before = vim.api.nvim_win_call(target, vim.fn.winsaveview)

        ui.reveal_cursor(target)

        assert.same(before, vim.api.nvim_win_call(target, vim.fn.winsaveview))
    end)

    it("clears floats stacked above the one over the cursor", function()
        vim.cmd("only")
        local target = vim.api.nvim_get_current_win()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines(200))
        open_bar()
        local bar_top, bar_bot = cover(float)

        -- A second float overlaps the top of the bar but stops short of the
        -- cursor row, as a hover above a side window would.
        upper_buf = vim.api.nvim_create_buf(false, true)
        upper = vim.api.nvim_open_win(upper_buf, false, {
            relative = "editor",
            row      = bar_top - 4,
            col      = 1,
            width    = 20,
            height   = 6,
            style    = "minimal",
            border   = "rounded",
        })
        local upper_top, upper_bot = cover(upper)
        assert.is_true(upper_top < bar_top)
        assert.is_true(upper_bot > bar_top and upper_bot < bar_bot)

        -- The bar covers the cursor; the upper float covers the row just above
        -- the bar, so clearing the bar alone would tuck the cursor under it.
        local lnum = upper_bot + 1 - text_top(target)
        at_top(target, lnum)
        assert.equals(upper_bot, cursor_row(target))

        ui.reveal_cursor(target)

        assert.equals(upper_top - 1, cursor_row(target))
        assert.same({ lnum, 0 }, vim.api.nvim_win_get_cursor(target))
    end)
end)
