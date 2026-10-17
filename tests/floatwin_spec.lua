local floatwin = require("lspnav.util.floatwin")

---@return integer
local function usable_lines()
    local has_statusline = vim.o.laststatus ~= 0 and vim.o.laststatus ~= 1
    return math.max(1, vim.o.lines - vim.o.cmdheight - (has_statusline and 1 or 0))
end

---@param bufnr integer
---@param desc string
---@return table?
local function buffer_map(bufnr, desc)
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if m.desc == desc then return m end
    end
end

describe("util.floatwin", function()
    local buf, win

    after_each(function()
        if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        if buf and vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
        win, buf = nil, nil
    end)

    it("lays the bar out across the bottom of the editor", function()
        local row, width, height = floatwin.layout(0.25)
        local usable = usable_lines()
        assert.equals(math.max(1, vim.o.columns - 4), width)
        assert.equals(usable, row + height + 2)
    end)

    it("opens a floating editor window without entering it", function()
        buf = vim.api.nvim_create_buf(false, true)
        local current = vim.api.nvim_get_current_win()
        win = floatwin.create_float_win(buf, { height_ratio = 0.25, title = " Test " })

        local cfg = vim.api.nvim_win_get_config(win)
        assert.equals("editor", cfg.relative)
        assert.equals(1, cfg.col)
        assert.equals(math.max(1, vim.o.columns - 4), cfg.width)
        assert.equals(usable_lines(), cfg.row + cfg.height + 2)
        assert.equals(current, vim.api.nvim_get_current_win())
    end)

    it("closes when a regular window gains focus", function()
        buf = vim.api.nvim_create_buf(false, true)
        win = floatwin.create_float_win(buf, {})
        assert.is_true(vim.api.nvim_win_is_valid(win))

        vim.cmd("vsplit")
        local closed = vim.wait(500, function() return not vim.api.nvim_win_is_valid(win) end)
        vim.cmd("only")
        assert.is_true(closed)
        win = nil
    end)

    it("reports the window when it closes", function()
        buf = vim.api.nvim_create_buf(false, true)
        local closed = false
        win = floatwin.create_float_win(buf, { on_delete = function() closed = true end })
        vim.api.nvim_win_close(win, true)
        assert.is_true(closed)
        win = nil
    end)

    it("moves the buffer into a split with <C-q>, keeping its contents", function()
        buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].bufhidden = "wipe"
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two" })

        local split
        win = floatwin.create_float_win(buf, {
            on_split = function(b)
                split = vim.api.nvim_open_win(b, true, { split = "below", win = -1 })
                return split
            end,
        })

        local map = assert(buffer_map(buf, "Open as split"))
        map.callback()

        assert.is_false(vim.api.nvim_win_is_valid(win))
        win = nil
        assert.is_true(vim.api.nvim_win_is_valid(split))
        assert.equals("", vim.api.nvim_win_get_config(split).relative)
        assert.equals(split, vim.api.nvim_get_current_win())
        assert.same({ "one", "two" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        assert.equals("wipe", vim.bo[buf].bufhidden)
        assert.is_nil(buffer_map(buf, "Close window"))

        vim.cmd("only")
        split = nil
    end)

    it("closes on <Esc>", function()
        buf = vim.api.nvim_create_buf(false, true)
        win = floatwin.create_float_win(buf, {})

        local map = assert(buffer_map(buf, "Close window"))
        map.callback()

        assert.is_false(vim.api.nvim_win_is_valid(win))
        win = nil
    end)

    it("leaves <C-q> unmapped without a split target", function()
        buf = vim.api.nvim_create_buf(false, true)
        win = floatwin.create_float_win(buf, {})
        assert.is_nil(buffer_map(buf, "Open as split"))
    end)
end)
