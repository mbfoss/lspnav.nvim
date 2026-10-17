-- ---------------------------------------------------------------------------
-- lspnav.references.locations
--
-- What a `textDocument/references` reply is made of: a flat list of positions,
-- normalized into rows and gathered by the file they sit in. The reply names
-- nothing, so a reference is only ever a place, and the row it renders shows the
-- line it sits on. The request itself is the Provider at the bottom, kept apart
-- so everything above it is a pure function a spec can call with no server.
-- ---------------------------------------------------------------------------

local readiness = require("lspnav.util.readiness")

local M = {}

--- One reference range on a line. Its own end line is kept because a range can
--- run past the line it starts on.
---@class lspnav.references.Span
---@field col integer 0-based column of the range start
---@field end_lnum integer 1-based last line the range covers
---@field end_col integer 0-based column of the range end

--- One reference: a position in a document. A `Location` carries no name, so
--- there is nothing here but where it is.
---@class lspnav.references.Location
---@field uri string document the reference is in
---@field lnum integer 1-based line of the range start
---@field col integer 0-based column of the range start
---@field end_lnum integer 1-based last line the range covers
---@field end_col integer 0-based column of the range end
---@field spans lspnav.references.Span[]? every reference on this line, first one included; set by `normalize` when a line holds several

--- The references that share one document, in position order.
---@class lspnav.references.FileGroup
---@field uri string
---@field path string display path, relative to the cwd or `~`
---@field items lspnav.references.Location[]

--- A directory in the reference tree, holding the folders and files beneath it.
---@class lspnav.references.Folder
---@field name string last segment of the display path ("" for the root)
---@field path string display path from the first segment down to this folder
---@field folders lspnav.references.Folder[]
---@field files lspnav.references.FileGroup[]
---@field count integer references every file beneath this folder holds

--- Path as the tree shows it: relative to the cwd, or `~` when outside it.
---@param uri string
---@return string
function M.display_name(uri)
    return vim.fn.fnamemodify(vim.uri_to_fname(uri), ":~:.")
end

--- Where a reply entry points. A `Location` carries `uri` with its `range`; a
--- `LocationLink` carries `targetUri`, the target's range under `targetRange`
--- and the name's own range under `targetSelectionRange`.
---@param entry table
---@return string? uri
---@return table? range
local function _target(entry)
    if type(entry) ~= "table" then return nil, nil end
    if type(entry.targetUri) == "string" then
        return entry.targetUri, entry.targetSelectionRange or entry.targetRange
    end
    if type(entry.uri) == "string" then
        return entry.uri, entry.range
    end
    return nil, nil
end

---@param a lspnav.references.Location
---@param b lspnav.references.Location
---@return boolean
local function _by_position(a, b)
    if a.uri ~= b.uri then return a.uri < b.uri end
    if a.lnum ~= b.lnum then return a.lnum < b.lnum end
    return a.col < b.col
end

-- Internal keys join their fields with NUL, which no URI, path or name can
-- contain: a printable separator could let two different positions produce the
-- same key.
--- Key identifying one reference. Servers that honour `includeDeclaration` may
--- list a position twice, once as the declaration and once as a use.
---@param loc lspnav.references.Location
---@return string
function M.identity(loc)
    return loc.uri .. "\0" .. loc.lnum .. "\0" .. loc.col
end

--- Key identifying the row a reference renders as. A row shows its line and
--- not its column, so references that share a line share a row.
---@param loc lspnav.references.Location
---@return string
local function _line_key(loc)
    return loc.uri .. "\0" .. loc.lnum
end

--- Normalize a `textDocument/references` reply into a position-sorted list.
--- Accepts both shapes a server may answer with, `Location[]` and
--- `LocationLink[]`, and drops entries carrying no usable position. Several
--- references on one line are merged into one location: with no column shown
--- they render as the same row, and every one of their ranges is kept in
--- `spans` so the source line can highlight each occurrence.
---@param result table[]? raw reply
---@return lspnav.references.Location[]
function M.normalize(result)
    local out = {}
    for _, entry in ipairs(result or {}) do
        local uri, range = _target(entry)
        local start = range and range.start
        if uri and start then
            local range_end = (range and range["end"]) or start
            out[#out + 1] = {
                uri      = uri,
                lnum     = start.line + 1,
                col      = start.character,
                end_lnum = range_end.line + 1,
                end_col  = range_end.character,
            }
        end
    end
    table.sort(out, _by_position)

    -- Sorted first, so the kept location is the line's first position and the
    -- spans come out in source order.
    local merged, by_line = {}, {}
    for _, loc in ipairs(out) do
        local key = _line_key(loc)
        local row = by_line[key]
        if not row then
            row = {
                uri      = loc.uri,
                lnum     = loc.lnum,
                col      = loc.col,
                end_lnum = loc.end_lnum,
                end_col  = loc.end_col,
                spans    = {},
            }
            by_line[key] = row
            merged[#merged + 1] = row
        end
        row.spans[#row.spans + 1] = {
            col      = loc.col,
            end_lnum = loc.end_lnum,
            end_col  = loc.end_col,
        }
    end
    return merged
end

--- Gather the references that share a document, ordered by display path.
---@param locations lspnav.references.Location[]
---@return lspnav.references.FileGroup[]
function M.group(locations)
    local groups = {}
    local by_uri = {}

    for _, loc in ipairs(locations) do
        local group = by_uri[loc.uri]
        if not group then
            group = { uri = loc.uri, path = M.display_name(loc.uri), items = {} }
            by_uri[loc.uri] = group
            groups[#groups + 1] = group
        end
        group.items[#group.items + 1] = loc
    end

    table.sort(groups, function(a, b) return a.path < b.path end)
    return groups
end

--- Split a display path into segments. A leading `/` becomes a segment of its
--- own, so an absolute path keeps its root in the tree.
---@param path string
---@return string[]
local function _segments(path)
    local segments = {}
    if path:sub(1, 1) == "/" then
        segments[1] = "/"
        path = path:sub(2)
    end
    for segment in path:gmatch("[^/]+") do
        segments[#segments + 1] = segment
    end
    return segments
end

---@param parent string
---@param segment string
---@return string
local function _join(parent, segment)
    if parent == "" then return segment end
    if parent == "/" then return "/" .. segment end
    return parent .. "/" .. segment
end

--- Sort a folder's children and count the references below it.
---@param folder lspnav.references.Folder
---@return integer
local function _finish(folder)
    table.sort(folder.folders, function(a, b) return a.name < b.name end)
    table.sort(folder.files, function(a, b) return a.path < b.path end)
    local count = 0
    for _, file in ipairs(folder.files) do count = count + #file.items end
    for _, sub in ipairs(folder.folders) do count = count + _finish(sub) end
    folder.count = count
    return count
end

--- Nest the file groups by the folders their display paths name, so the tree
--- view can show the directory hierarchy. Returns the virtual root: its
--- `folders` and `files` are the top-level entries, and its `path` and `name`
--- are empty. Folders sort before files, and siblings sort by name.
---@param groups lspnav.references.FileGroup[]
---@return lspnav.references.Folder
function M.hierarchy(groups)
    local root = { name = "", path = "", folders = {}, files = {}, count = 0 }
    local by_path = {}

    for _, group in ipairs(groups) do
        local segments = _segments(group.path)
        local folder = root
        for i = 1, #segments - 1 do
            local path = _join(folder.path, segments[i])
            local sub = by_path[path]
            if not sub then
                sub = { name = segments[i], path = path, folders = {}, files = {}, count = 0 }
                by_path[path] = sub
                folder.folders[#folder.folders + 1] = sub
            end
            folder = sub
        end
        folder.files[#folder.files + 1] = group
    end

    _finish(root)
    return root
end

--- Merge folder chains that hold no files, so `lua/lspnav/references` becomes
--- one row instead of three. A folder that holds files, or that branches into
--- several subfolders, stays its own node; that is where the nesting carries
--- information. Mutates the freshly built folders `hierarchy()` returns.
---@param folders lspnav.references.Folder[]
---@return lspnav.references.Folder[]
function M.compact(folders)
    local out = {}
    for _, folder in ipairs(folders) do
        folder.folders = M.compact(folder.folders)
        while #folder.folders == 1 and #folder.files == 0 do
            local child = folder.folders[1]
            folder.name = _join(folder.name, child.name)
            folder.path = child.path
            folder.folders = child.folders
            folder.files = child.files
            folder.count = child.count
        end
        out[#out + 1] = folder
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Provider: references for a position over LSP
-- ---------------------------------------------------------------------------

local _METHOD = "textDocument/references"

---@class lspnav.references.locations.Provider.Handlers
---@field on_locations fun(locations: lspnav.references.Location[], partial: boolean) reply received, possibly empty; `partial` is true when the server was still doing background work
---@field on_unavailable fun(reason: string) the request could not be made or failed

---@class lspnav.references.locations.Provider
---@field new fun(self:lspnav.references.locations.Provider):lspnav.references.locations.Provider
---@field private _request_counter integer
local Provider = {}
Provider.__index = Provider

function Provider:new()
    local obj = setmetatable({}, self)
    if obj.init then obj:init() end
    return obj
end

function Provider:init()
    self._request_counter = 0
end

--- Ask the client serving `textDocument/references` for every reference to the
--- symbol at the cursor of `winid`. A position is all the server needs: unlike
--- the call hierarchy there is no prepare step, and no name to resolve first,
--- since the reply is a list of places rather than a tree of symbols.
---@param bufnr integer
---@param winid integer window whose cursor names the symbol
---@param include_declaration boolean count the declaration itself as a reference
---@param handlers lspnav.references.locations.Provider.Handlers
function Provider:references(bufnr, winid, include_declaration, handlers)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_win_is_valid(winid) then
        handlers.on_unavailable("No buffer")
        return
    end

    local client = vim.lsp.get_clients({ bufnr = bufnr, method = _METHOD })[1]
    if not client then
        handlers.on_unavailable("No references support")
        return
    end

    self._request_counter = self._request_counter + 1
    local request_id = self._request_counter

    local params = vim.lsp.util.make_position_params(winid, client.offset_encoding)
    params.context = { includeDeclaration = include_declaration and true or false }

    -- Checked at both ends of the round trip: a server that was busy when
    -- asked may still answer from the work it has done so far, and one that
    -- started after the request can answer from a state still being built.
    local partial = readiness.busy(client)

    client:request(_METHOD, params, function(err, result)
        -- Drop replies overtaken by a newer request.
        if request_id ~= self._request_counter then return end

        if err then
            handlers.on_unavailable("References request failed")
            return
        end

        -- A null result can arrive as vim.NIL, so check the type.
        handlers.on_locations(
            M.normalize(type(result) == "table" and result or nil),
            partial or readiness.busy(client))
    end, bufnr)
end

M.Provider = Provider

return M
