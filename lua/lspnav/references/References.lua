local TreeBuffer = require("lspnav.util.TreeBuffer")
local ui         = require("lspnav.util.ui")
local hover      = require("lspnav.util.hover")
local kinds      = require("lspnav.symboltree.kinds")
local locations  = require("lspnav.references.locations")

--- What the window is showing references to, kept so the root row can name the
--- symbol and `R` can ask the question again.
---@class lspnav.references.Query
---@field bufnr integer buffer the question was asked in
---@field uri string document the question was asked in
---@field lnum integer 1-based line the cursor was on
---@field col integer 0-based column the cursor was on
---@field name string? the word under the cursor, when there was one
---@field count integer references the server returned
---@field partial boolean? the server was still doing background work, so the list may be incomplete

--- What one line of the tree holds. Exactly one of `text`, `query`, `group` and
--- `loc` is set, and that is what the formatter switches on: a placeholder, the
--- root, a file heading, or a reference.
---@class lspnav.references.ItemData
---@field text string? placeholder rows only
---@field query lspnav.references.Query? the root row only
---@field folder lspnav.references.Folder? folder rows only
---@field group lspnav.references.FileGroup? file heading rows only
---@field loc lspnav.references.Location? reference rows only
---@field label string? the name a folder or file row shows
---@field line string? the source line of a reference row, when it could be read
---@field hl_spans integer[][]? byte ranges in `line` holding referenced text; one per reference on the line
---@field icon string?
---@field icon_hl string?

---@type lspnav.symboltree.Kind
local _PLACEHOLDER_KIND = { name = "Placeholder", icon = "󰋗", hl = "Comment" }

---@type lspnav.symboltree.Kind
local _FILE_KIND = kinds.get(1)

--- The root row stands for the symbol, not for a file.
---@type lspnav.symboltree.Kind
local _ROOT_KIND = { name = "Symbol", icon = "󰌹", hl = "Title" }

---@type lspnav.symboltree.Kind
local _FOLDER_KIND = { name = "Folder", icon = "󰉋", hl = "Directory" }

--- The views, in the order `<Tab>` cycles them.
---@type string[]
local _VIEWS = { "tree", "flat" }

---@param view string?
---@return "tree"|"flat"
local function _view_or_default(view)
    for _, name in ipairs(_VIEWS) do
        if view == name then return name end
    end
    return _VIEWS[1]
end

--- Highlight for the referenced name inside a source-line extract. A `default`
--- link, so a colorscheme or a user `nvim_set_hl` call wins over it.
local _symbol_hl = "LspnavReferencesSymbol"

--- Highlight for the indent guides. A `default` link, so a colorscheme or a user
--- `nvim_set_hl` call wins over it.
local _indent_guide_hl = "LspnavIndentGuide"

---Link the reference name onto `Label` and the indent guide group onto `NonText`.
local function _setup_highlights()
    vim.api.nvim_set_hl(0, _symbol_hl, { link = "Label", default = true })
    vim.api.nvim_set_hl(0, _indent_guide_hl, { link = "NonText", default = true })
end

local function _show_help()
    local help_text = { [[
`<CR>`    Expand/collapse
`Tab`     Switch between tree and flat views
`o`       Jump to the reference, keep focus in the tree
`K`       Hover info (file, line, source line)
`R`       Ask the server again
`<C-q>`   Open as a split (float only)
`<Esc>`   Close the window (float only)
`g?`      Show this help
]]
    }

    hover.show(table.concat(help_text, "\n"), {
        title = "References",
        syntax = "markdown",
    })
end

--- Display columns a source line is cut to, so one minified line cannot take the
--- whole window.
local _MAX_LINE = 200

---@param data lspnav.references.ItemData
---@param show_line boolean
---@return string[][] chunks, string[][] virt_chunks, string? line_hl
local function _formatter(data, show_line)
    if not data then return {}, {} end

    if data.text then
        return { { data.icon, data.icon_hl }, { " " }, { data.text, "Comment" } }, {}
    end

    if data.query then
        local query = data.query
        -- The root names the symbol; where it was asked is already visible in
        -- the source window behind the list. A cursor that was not on a word
        -- falls back to the position, so the row still says what it is about.
        local name = query.name
        if name == nil or name == "" then
            name = locations.display_name(query.uri) .. ":" .. query.lnum
        end
        local chunks = {
            { "REFERENCES", "Title" },
            { " " },
            { data.icon, data.icon_hl },
            { " " },
            { name, "Directory" },
            { " " },
            { ("(%d)"):format(query.count), "Comment" },
        }
        -- The root row is the first row in both views, so the caveat sits on
        -- the same line whichever view is showing. "May be" rather than
        -- "partial results": the same wording has to fit an empty reply, and
        -- the server being busy does not prove anything was left out.
        if query.partial then
            table.insert(chunks, { " " })
            table.insert(chunks, { "(may be incomplete)", "WarningMsg" })
        end
        return chunks, {}
    end

    if data.folder then
        local name = data.label or data.folder.name
        -- The `/` segment of an absolute path is a folder name already.
        if name ~= "/" then name = name .. "/" end
        return {
            { data.icon, data.icon_hl },
            { " " },
            { name, "Directory" },
            { " " },
            { ("(%d)"):format(data.folder.count), "Comment" },
        }, {}
    end

    if data.group then
        return {
            { data.icon, data.icon_hl },
            { " " },
            { data.label or data.group.path, "Title" },
            { " " },
            { ("(%d)"):format(#data.group.items), "Comment" },
        }, {}
    end

    -- A reference has no name of its own, so the row is its line followed by the
    -- source line it sits on: enough to tell one use from another at a glance.
    local loc = data.loc
    local chunks = {
        { tostring(loc.lnum), "LineNr" },
    }
    if show_line and data.line and data.line ~= "" then
        table.insert(chunks, { " " })
        local spans = data.hl_spans
        if spans and #spans > 0 then
            -- Split the extract around every referenced range on the line, so
            -- each occurrence of the name carries the symbol highlight.
            local pos = 0
            for _, span in ipairs(spans) do
                local s = math.max(span[1], pos)
                local e = math.min(span[2], #data.line)
                if s < e then
                    if s > pos then table.insert(chunks, { data.line:sub(pos + 1, s) }) end
                    table.insert(chunks, { data.line:sub(s + 1, e), _symbol_hl })
                    pos = e
                end
            end
            if pos < #data.line then table.insert(chunks, { data.line:sub(pos + 1) }) end
        else
            table.insert(chunks, { data.line })
        end
    end
    return chunks, {}
end

--- Paths of the loaded buffers, mapped to their bufnr. Reading the line under a
--- reference must not put a document in the buffer list, so only documents
--- already open are read from memory; the rest are read off disk.
---@return table<string, integer>
local function _loaded_buffers()
    local map = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            local name = vim.api.nvim_buf_get_name(buf)
            if name ~= "" then map[name] = buf end
        end
    end
    return map
end

---@param raw string
---@return string
local function _expand_tabs(raw)
    return (raw:gsub("\t", "    "))
end

--- The text of the line `loc` sits on, stripped of its indentation and cut to a
--- display width, plus the byte ranges the line's references occupy in what is
--- returned. An open document is read from its buffer, so unsaved edits are
--- what shows; otherwise the file is read from disk up to that line.
---@param loaded table<string, integer>
---@param loc lspnav.references.Location
---@return string? text, integer[][]? hl_spans
local function _line_text(loaded, loc)
    local buf = loaded[vim.uri_to_fname(loc.uri)]
    local raw
    if buf then
        raw = vim.api.nvim_buf_get_lines(buf, loc.lnum - 1, loc.lnum, false)[1]
    else
        local ok, lines = pcall(vim.fn.readfile, vim.uri_to_fname(loc.uri), "", loc.lnum)
        if ok and type(lines) == "table" then raw = lines[#lines] end
    end
    if type(raw) ~= "string" then return nil end

    -- The row drops the indentation and expands tabs, so the columns the server
    -- reported have to make the same trip before they can split the text.
    local lead = #(raw:match("^%s*") or "")
    local body = raw:sub(lead + 1)
    local text = _expand_tabs(body)

    --- Byte offset in `text` of a 0-based byte column of `raw`.
    ---@param col integer
    ---@return integer
    local function offset(col)
        return #(_expand_tabs(body:sub(1, math.max(0, col - lead))))
    end

    -- Every reference on the line carries its own range; one that runs past
    -- this line marks the extract up to its end.
    local spans = {}
    for _, span in ipairs(loc.spans or { { col = loc.col, end_lnum = loc.end_lnum, end_col = loc.end_col } }) do
        local s = offset(span.col)
        local e = span.end_lnum == loc.lnum and offset(span.end_col) or #text
        if s < e then spans[#spans + 1] = { s, e } end
    end

    local limit = #text
    if vim.fn.strchars(text) > _MAX_LINE then
        limit = #vim.fn.strcharpart(text, 0, _MAX_LINE - 1)
        text = vim.fn.strcharpart(text, 0, _MAX_LINE - 1) .. "…"
    end

    -- A range can reach past what the cut extract shows; keep the highlights
    -- inside it, and drop any whose name was cut off.
    local clamped = {}
    for _, span in ipairs(spans) do
        local s = math.min(span[1], limit)
        local e = math.min(span[2], limit)
        if s < e then clamped[#clamped + 1] = { s, e } end
    end
    if #clamped == 0 then return text end
    return text, clamped
end

--- The word under a position, so the root row can name the symbol. The reply
--- lists places only, so the name has to come off the source line. `\k` follows
--- the buffer's own `iskeyword`, which `nvim_buf_call` makes current: the
--- source buffer is not necessarily the current one when a query is re-asked.
---@param bufnr integer
---@param lnum integer 1-based line
---@param col integer 0-based byte column
---@return string? name
local function _word_at(bufnr, lnum, col)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
        return nil
    end

    local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
    if not line then return nil end

    return vim.api.nvim_buf_call(bufnr, function()
        local from = 0
        while from <= #line do
            local match = vim.fn.matchstrpos(line, "\\k\\+", from)
            local start, finish = match[2], match[3]
            if start < 0 then return nil end
            if col >= start and col < finish then return match[1] end
            if start > col then return nil end
            from = finish
        end
        return nil
    end)
end

--- Load the document `uri` names into a buffer, without displaying it.
---@param uri string
---@return integer? bufnr
local function _uri_bufnr(uri)
    local bufnr = vim.uri_to_bufnr(uri)
    if not vim.api.nvim_buf_is_valid(bufnr) then return nil end
    if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end
    return bufnr
end

--- A non-floating window showing `bufnr`, so a re-ask can aim at the buffer the
--- question was first asked in even after that window has gone.
---@param bufnr integer
---@return integer? winid
local function _win_for_buf(bufnr)
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        if vim.api.nvim_win_get_config(win).relative == "" then return win end
    end
    return nil
end

---@class lspnav.References.Opts
---@field include_declaration boolean? count the declaration itself (default true)
---@field show_line boolean? show the source line each reference sits on (default true)
---@field view "tree"|"flat"? tree compacts folder chains (default "tree")
---@field auto_expand boolean? expand every folder and file once resolved (default true)
---@field indent_guides boolean? draw vertical indent guides (default false)

---@class lspnav.References
---@field new fun(self:lspnav.References, opts:lspnav.References.Opts?):lspnav.References
---@field private _treebuf lspnav.util.TreeBuffer
---@field private _provider lspnav.references.locations.Provider
---@field private _query lspnav.references.Query?
---@field private _view "tree"|"flat"
---@field private _list lspnav.references.Location[]? the reply currently shown
---@field private _lines table<string, {text:string, hl_spans:integer[][]?}>? source line per reference identity
---@field private _ids table<string, any> keys to the rows ids they were rendered as
---@field private _generation integer invalidates in-flight replies
---@field private _next_id integer
---@field private _opts lspnav.References.Opts
local References = {}
References.__index = References

function References:new(...)
    local obj = setmetatable({}, self)
    if obj.init then obj:init(...) end
    return obj
end

---@param opts lspnav.References.Opts?
function References:init(opts)
    self._opts       = opts and vim.deepcopy(opts) or {}
    self._provider   = locations.Provider:new()
    self._query      = nil
    self._view       = _view_or_default(self._opts.view)
    self._list       = nil
    self._lines      = nil
    self._ids        = {}
    self._generation = 0
    self._next_id    = 0

    self:_setup_tree()
end

function References:_setup_tree()
    assert(not self._treebuf)

    _setup_highlights()
    self._treebuf = TreeBuffer.new({
        filetype  = "lspnav-references",
        formatter = function(_, data)
            return _formatter(data, self._opts.show_line ~= false)
        end,
        indent_guides = self._opts.indent_guides == true,
        indent_guide_hl = _indent_guide_hl,
    })

    self._treebuf:subscribe({
        -- Only fires for rows that cannot expand, which here is a reference:
        -- folders, file headings and the root fold instead.
        on_selection = function(_, data)
            if data and data.loc then self:_jump_to(data.loc, true) end
        end,
    })
end

---@return any
function References:_new_id()
    self._next_id = self._next_id + 1
    return self._next_id
end

---@return integer bufnr
function References:create_buffer()
    local bufnr, created = self._treebuf:create_buffer(function()
        self:_on_buffer_deleted()
    end)

    if not created then return bufnr end

    ---@param fn fun(data:lspnav.references.ItemData)
    local function with_location(fn)
        local item = self._treebuf:get_cursor_item()
        local data = item and item.data ---@type lspnav.references.ItemData?
        if data and data.loc then fn(data) end
    end

    local keymaps = {
        ["<Tab>"] = {
            function() self:switch_view() end,
            "Switch between tree and flat views",
        },
        ["o"] = {
            function() with_location(function(data) self:_jump_to(data.loc, false) end) end,
            "Jump to reference (keep focus)",
        },
        ["K"] = {
            function() with_location(function(data) self:_show_hover(data) end) end,
            "Show reference info",
        },
        ["R"] = {
            function() self:refresh() end,
            "Ask the server again",
        },
        ["g?"] = {
            function() _show_help() end,
            "Show Help",
        },
    }

    assert(bufnr > 0)
    for key, map in pairs(keymaps) do
        vim.api.nvim_buf_set_keymap(bufnr, "n", key, "", { callback = map[1], desc = map[2] })
    end

    if not self._query then
        self:_show_placeholder("No references")
    end

    return bufnr
end

function References:get_bufnr()
    return self._treebuf:get_bufnr()
end

function References:_on_buffer_deleted()
    -- Invalidate replies still in flight: they would render into a buffer that
    -- no longer exists.
    self._generation = self._generation + 1
    self._query = nil
    self._list = nil
    self._lines = nil
    self._ids = {}
end

---@param text string
function References:_show_placeholder(text)
    if self._treebuf:get_bufnr() == -1 then return end
    self._treebuf:clear_items()
    self._treebuf:add_item(nil, {
        id   = self:_new_id(),
        data = { text = text, icon = _PLACEHOLDER_KIND.icon, icon_hl = _PLACEHOLDER_KIND.hl },
    })
end

--- Resolve the symbol at the cursor of `winid` and list its references.
---@param bufnr integer
---@param winid integer window whose cursor names the symbol
function References:show_from_cursor(bufnr, winid)
    -- The question is asked about where the cursor is now, so it is read before
    -- the reply lands rather than from the reply, which names nothing.
    local cursor = vim.api.nvim_win_get_cursor(winid)
    local query = {
        bufnr = bufnr,
        uri   = vim.uri_from_bufnr(bufnr),
        lnum  = cursor[1],
        col   = cursor[2],
        name  = _word_at(bufnr, cursor[1], cursor[2]),
        count = 0,
    }

    self._generation = self._generation + 1
    local generation = self._generation

    self:_show_placeholder("Finding references…")

    self._provider:references(bufnr, winid, self._opts.include_declaration ~= false, {
        on_locations = function(list, partial)
            if generation ~= self._generation then return end
            if #list == 0 then
                -- Keep the query so `R` can ask again: an empty reply while
                -- the server is busy is exactly when the user will want to.
                self._query = query
                self._list = nil
                self:_show_placeholder(partial and "No references (may be incomplete)" or "No references")
                return
            end
            query.partial = partial or nil
            self:_populate(list, query)
        end,
        on_unavailable = function(reason)
            if generation ~= self._generation then return end
            self._query = nil
            self._list = nil
            self:_show_placeholder(reason)
        end,
    })
end

--- Ask the same question again, from the buffer it was first asked in.
function References:refresh()
    local query = self._query
    if not query then return end
    if not vim.api.nvim_buf_is_valid(query.bufnr) then return end

    local winid = _win_for_buf(query.bufnr)
    if not winid then return end

    self:show_from_cursor(query.bufnr, winid)
end

--- Keep the reply around and render it in the current view. The whole reply is
--- known at once, so every row is built here rather than fetched on expand.
---@param list lspnav.references.Location[]
---@param query lspnav.references.Query
function References:_populate(list, query)
    if self._treebuf:get_bufnr() == -1 then return end

    query.count = #list
    self._query = query
    self._list = list

    -- Read each source line once: switching views re-renders the rows without
    -- touching the filesystem again.
    self._lines = nil
    if self._opts.show_line ~= false then
        local loaded = _loaded_buffers()
        local lines = {}
        for _, loc in ipairs(list) do
            local text, hl_spans = _line_text(loaded, loc)
            if text then
                lines[locations.identity(loc)] = { text = text, hl_spans = hl_spans }
            end
        end
        self._lines = lines
    end

    self:_render()
end

--- Move to the next view, re-rendering the rows already fetched.
function References:switch_view()
    for i, name in ipairs(_VIEWS) do
        if name == self._view then
            self._view = _VIEWS[i % #_VIEWS + 1]
            break
        end
    end
    self:_render()
end

--- Render `_list` in the current view, keeping the cursor on the row it was on
--- when possible.
function References:_render()
    local query, list = self._query, self._list
    if not query or not list or self._treebuf:get_bufnr() == -1 then return end

    local cursor_key = self:_cursor_key()

    self._treebuf:clear_items()
    self._ids = {}

    local root_id = self:_new_id()
    self._ids.root = root_id
    self._treebuf:add_item(nil, {
        id         = root_id,
        data       = { query = query, icon = _ROOT_KIND.icon, icon_hl = _ROOT_KIND.hl },
        expandable = true,
        expanded   = true,
    })

    local groups = locations.group(list)
    if self._view == "flat" then
        self:_render_children(root_id, nil, groups)
    else
        local root = locations.hierarchy(groups)
        self:_render_children(root_id, locations.compact(root.folders), root.files)
    end

    if cursor_key and self._ids[cursor_key] then
        self._treebuf:set_cursor_by_id(self._ids[cursor_key])
    end
end

--- What the cursor sits on, as a key into `_ids`, so a re-render can return to
--- it. Nil on a placeholder.
---@return string?
function References:_cursor_key()
    local item = self._treebuf:get_cursor_item()
    local data = item and item.data ---@type lspnav.references.ItemData?
    if not data then return nil end
    if data.query then return "root" end
    if data.folder then return "dir\0" .. data.folder.path end
    if data.group then return "file\0" .. data.group.uri end
    if data.loc then return "loc\0" .. locations.identity(data.loc) end
    return nil
end

--- Add folders and files under `parent_id`, each before its own children. A nil
--- `folders` means the flat view: file headings stand on their own and show
--- their whole path.
---@param parent_id any
---@param folders lspnav.references.Folder[]?
---@param files lspnav.references.FileGroup[]
function References:_render_children(parent_id, folders, files)
    local defs, entries = {}, {}

    for _, folder in ipairs(folders or {}) do
        local id = self:_new_id()
        self._ids["dir\0" .. folder.path] = id
        defs[#defs + 1] = {
            id         = id,
            data       = { folder = folder, icon = _FOLDER_KIND.icon, icon_hl = _FOLDER_KIND.hl },
            expandable = true,
            expanded   = self._opts.auto_expand ~= false,
        }
        entries[#entries + 1] = { folder = folder, id = id }
    end

    for _, group in ipairs(files) do
        local id = self:_new_id()
        self._ids["file\0" .. group.uri] = id
        defs[#defs + 1] = {
            id = id,
            data = {
                group = group,
                -- A file row in the tree lives under the folders that name its
                -- path already, so it shows only its basename.
                label    = folders and vim.fn.fnamemodify(group.path, ":t") or nil,
                icon     = _FILE_KIND.icon,
                icon_hl  = _FILE_KIND.hl,
            },
            expandable = true,
            expanded   = self._opts.auto_expand ~= false,
        }
        entries[#entries + 1] = { group = group, id = id }
    end

    self._treebuf:set_children(parent_id, defs)

    -- Children are added once their parent exists; an expanded parent renders
    -- them as soon as they arrive.
    for _, entry in ipairs(entries) do
        if entry.folder then
            self:_render_children(entry.id, entry.folder.folders, entry.folder.files)
        else
            self:_render_locations(entry.id, entry.group.items)
        end
    end
end

--- Add the reference rows of one file.
---@param parent_id any
---@param items lspnav.references.Location[]
function References:_render_locations(parent_id, items)
    local children = {}
    for i, loc in ipairs(items) do
        local data = { loc = loc } ---@type lspnav.references.ItemData
        local line = self._lines and self._lines[locations.identity(loc)]
        if line then
            data.line     = line.text
            data.hl_spans = line.hl_spans
        end
        local id = self:_new_id()
        self._ids["loc\0" .. locations.identity(loc)] = id
        children[i] = { id = id, data = data, expandable = false }
    end
    self._treebuf:set_children(parent_id, children)
end

---@param loc lspnav.references.Location
---@param activate boolean focus the window we jumped into
function References:_jump_to(loc, activate)
    local bufnr = _uri_bufnr(loc.uri)
    if not bufnr then return end

    local winid = ui.smart_open_buffer(bufnr, loc.lnum, loc.col, activate)
    if activate == false then
        -- Focus stays in the float, which may cover the line just jumped to.
        ui.reveal_cursor(winid)
    end
end

---@param data lspnav.references.ItemData
function References:_show_hover(data)
    if data.folder then
        local lines = {
            "# " .. data.folder.path,
            "",
            "- **Folders**: " .. #data.folder.folders,
            "- **Files**: " .. #data.folder.files,
            "- **References**: " .. data.folder.count,
        }
        hover.show(table.concat(lines, "\n"), {
            title = "Folder",
            syntax = "markdown",
        })
        return
    end

    if data.group then
        local lines = {
            "# " .. data.group.path,
            "",
            "- **References**: " .. #data.group.items,
        }
        hover.show(table.concat(lines, "\n"), {
            title = "File",
            syntax = "markdown",
        })
        return
    end

    local loc = data.loc
    local lines = {
        "# " .. locations.display_name(loc.uri),
        "",
        "- **Line**: " .. loc.lnum,
    }
    if data.line and data.line ~= "" then
        table.insert(lines, "- **Source**: `" .. data.line .. "`")
    end

    hover.show(table.concat(lines, "\n"), {
        title = "Reference",
        syntax = "markdown",
    })
end

return References
