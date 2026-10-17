local locations = require("lspnav.references.locations")

---@param sl integer
---@param sc integer
---@param el integer
---@param ec integer
local function range(sl, sc, el, ec)
    return { start = { line = sl, character = sc }, ["end"] = { line = el, character = ec } }
end

---@param uri string
---@param r table
local function location(uri, r)
    return { uri = uri, range = r }
end

describe("references.locations.normalize", function()
    it("converts Location positions to 1-based lines", function()
        local out = locations.normalize({ location("file:///a.lua", range(4, 2, 6, 8)) })
        assert.equals(1, #out)
        assert.equals("file:///a.lua", out[1].uri)
        assert.equals(5, out[1].lnum)
        assert.equals(2, out[1].col)
        assert.equals(7, out[1].end_lnum)
        assert.equals(8, out[1].end_col)
    end)

    it("reads a LocationLink from its target fields", function()
        local out = locations.normalize({ {
            targetUri = "file:///b.lua",
            targetRange = range(9, 0, 12, 1),
            targetSelectionRange = range(9, 4, 9, 9),
        } })
        assert.equals(1, #out)
        assert.equals("file:///b.lua", out[1].uri)
        assert.equals(10, out[1].lnum)
        assert.equals(4, out[1].col)
        -- The selection range names the symbol, so its end is what the extract highlights.
        assert.equals(9, out[1].end_col)
    end)

    it("falls back to the target range when no selection range is sent", function()
        local out = locations.normalize({
            { targetUri = "file:///b.lua", targetRange = range(2, 1, 3, 0) },
        })
        assert.equals(3, out[1].lnum)
        assert.equals(1, out[1].col)
    end)

    it("reads a LocationLink in preference to uri and range", function()
        local out = locations.normalize({ {
            uri = "file:///ignored.lua",
            range = range(0, 0, 0, 1),
            targetUri = "file:///b.lua",
            targetRange = range(2, 3, 2, 8),
        } })
        assert.equals("file:///b.lua", out[1].uri)
        assert.equals(3, out[1].lnum)
    end)

    it("drops entries with no usable position", function()
        assert.equals(0, #locations.normalize({
            { name = "no_range", kind = 12 },
            { uri = "file:///a.lua" },
            { uri = "file:///a.lua", range = {} },
            "junk",
        }))
    end)

    it("sorts by document then position", function()
        local out = locations.normalize({
            location("file:///b.lua", range(1, 0, 1, 5)),
            location("file:///a.lua", range(9, 0, 9, 5)),
            location("file:///a.lua", range(2, 0, 2, 5)),
        })
        assert.equals("file:///a.lua", out[1].uri)
        assert.equals(3, out[1].lnum)
        assert.equals("file:///a.lua", out[2].uri)
        assert.equals(10, out[2].lnum)
        assert.equals("file:///b.lua", out[3].uri)
    end)

    it("drops the same position sent twice", function()
        local out = locations.normalize({
            location("file:///a.lua", range(4, 2, 4, 9)),
            location("file:///a.lua", range(4, 2, 4, 9)),
        })
        assert.equals(1, #out)
    end)

    it("merges references on the same line, keeping every span", function()
        local out = locations.normalize({
            location("file:///a.lua", range(4, 20, 4, 23)),
            location("file:///a.lua", range(4, 2, 4, 5)),
        })
        assert.equals(1, #out)
        assert.equals(2, out[1].col)
        assert.equals(5, out[1].end_col)
        assert.equals(2, #out[1].spans)
        assert.equals(2, out[1].spans[1].col)
        assert.equals(5, out[1].spans[1].end_col)
        assert.equals(20, out[1].spans[2].col)
        assert.equals(23, out[1].spans[2].end_col)
    end)

    it("keeps references on different lines apart", function()
        local out = locations.normalize({
            location("file:///a.lua", range(4, 2, 4, 5)),
            location("file:///a.lua", range(5, 2, 5, 5)),
        })
        assert.equals(2, #out)
    end)

    it("returns an empty list for nil or empty input", function()
        assert.equals(0, #locations.normalize(nil))
        assert.equals(0, #locations.normalize({}))
    end)
end)

describe("references.locations.identity", function()
    it("distinguishes positions, within a document and across documents", function()
        local a = locations.normalize({ location("file:///a.lua", range(1, 0, 1, 5)) })[1]
        local b = locations.normalize({ location("file:///a.lua", range(2, 0, 2, 5)) })[1]
        local c = locations.normalize({ location("file:///b.lua", range(1, 0, 1, 5)) })[1]
        assert.not_equals(locations.identity(a), locations.identity(b))
        assert.not_equals(locations.identity(a), locations.identity(c))
    end)
end)

describe("references.locations.group", function()
    it("gathers references by document, ordered by path", function()
        local list = locations.normalize({
            location("file:///b.lua", range(1, 0, 1, 5)),
            location("file:///a.lua", range(8, 0, 8, 5)),
            location("file:///a.lua", range(2, 0, 2, 5)),
        })
        local groups = locations.group(list)
        assert.equals(2, #groups)
        assert.equals("file:///a.lua", groups[1].uri)
        assert.equals(2, #groups[1].items)
        assert.equals("file:///b.lua", groups[2].uri)
        assert.equals(1, #groups[2].items)
    end)

    it("keeps the references of one document in position order", function()
        local list = locations.normalize({
            location("file:///a.lua", range(8, 0, 8, 5)),
            location("file:///a.lua", range(2, 0, 2, 5)),
        })
        local items = locations.group(list)[1].items
        assert.equals(2, #items)
        assert.equals(3, items[1].lnum)
        assert.equals(9, items[2].lnum)
    end)

    it("carries the uri each group stands for", function()
        local list = locations.normalize({ location("file:///a.lua", range(0, 0, 0, 1)) })
        local group = locations.group(list)[1]
        assert.equals("file:///a.lua", group.uri)
        assert.is_truthy(group.path:find("a%.lua$"))
    end)

    it("returns nothing for an empty list", function()
        assert.equals(0, #locations.group({}))
    end)
end)

---@param path string
---@param count integer?
---@return lspnav.references.FileGroup
local function file_group(path, count)
    local items = {}
    for i = 1, count or 1 do
        items[i] = { uri = "file:///" .. path, lnum = i, col = 0, end_lnum = i }
    end
    return { uri = "file:///" .. path, path = path, items = items }
end

describe("references.locations.hierarchy", function()
    it("nests files under the folders their paths name", function()
        local root = locations.hierarchy({
            file_group("lua/lspnav/references/tree.lua", 2),
            file_group("lua/lspnav/references/config.lua", 1),
            file_group("lua/lspnav/init.lua", 3),
            file_group("tests/references_spec.lua", 4),
        })
        assert.equals(2, #root.folders)
        assert.equals(0, #root.files)
        assert.equals("lua", root.folders[1].name)
        assert.equals("tests", root.folders[2].name)
        assert.equals("lua/lspnav", root.folders[1].folders[1].path)
        assert.equals("lua/lspnav/references", root.folders[1].folders[1].folders[1].path)
    end)

    it("counts every reference under a folder", function()
        local root = locations.hierarchy({
            file_group("lua/a.lua", 2),
            file_group("lua/sub/b.lua", 3),
            file_group("tests/c.lua", 4),
        })
        assert.equals(5, root.folders[1].count)
        assert.equals(3, root.folders[1].folders[1].count)
        assert.equals(9, root.count)
    end)

    it("keeps each file's whole path for the flat view", function()
        local root = locations.hierarchy({ file_group("lua/a.lua") })
        assert.equals("lua/a.lua", root.folders[1].files[1].path)
    end)

    it("puts files that sit at the root directly under it", function()
        local root = locations.hierarchy({ file_group("a.lua", 2) })
        assert.equals(0, #root.folders)
        assert.equals(1, #root.files)
        assert.equals("a.lua", root.files[1].path)
        assert.equals(2, root.count)
    end)

    it("keeps an absolute path's root segment", function()
        local root = locations.hierarchy({ file_group("/abs/a.lua") })
        assert.equals("/", root.folders[1].name)
        assert.equals("/abs", root.folders[1].folders[1].path)
        assert.equals("/abs/a.lua", root.folders[1].folders[1].files[1].path)
    end)

    it("sorts folders by name and files by path", function()
        local root = locations.hierarchy({
            file_group("b/x.lua"),
            file_group("a/z.lua"),
            file_group("a/y.lua"),
        })
        assert.equals("a", root.folders[1].name)
        assert.equals("b", root.folders[2].name)
        assert.equals("a/y.lua", root.folders[1].files[1].path)
        assert.equals("a/z.lua", root.folders[1].files[2].path)
    end)

    it("returns an empty root for no groups", function()
        local root = locations.hierarchy({})
        assert.equals(0, #root.folders)
        assert.equals(0, #root.files)
        assert.equals(0, root.count)
    end)
end)

describe("references.locations.compact", function()
    it("merges a chain of folders that hold no files into one node", function()
        local root = locations.hierarchy({ file_group("a/b/c/x.lua", 2) })
        local folders = locations.compact(root.folders)
        assert.equals(1, #folders)
        assert.equals("a/b/c", folders[1].name)
        assert.equals("a/b/c", folders[1].path)
        assert.equals(1, #folders[1].files)
        assert.equals(2, folders[1].count)
    end)

    it("stops at a folder that holds files", function()
        local root = locations.hierarchy({
            file_group("a/x.lua"),
            file_group("a/b/y.lua"),
        })
        local folders = locations.compact(root.folders)
        assert.equals("a", folders[1].name)
        assert.equals(1, #folders[1].files)
        assert.equals("b", folders[1].folders[1].name)
        assert.equals("a/b", folders[1].folders[1].path)
    end)

    it("stops at a branch", function()
        local root = locations.hierarchy({
            file_group("a/b/x.lua"),
            file_group("a/c/y.lua"),
        })
        local folders = locations.compact(root.folders)
        assert.equals("a", folders[1].name)
        assert.equals(2, #folders[1].folders)
        assert.equals("b", folders[1].folders[1].name)
        assert.equals("c", folders[1].folders[2].name)
    end)

    it("keeps an absolute chain's leading slash", function()
        local root = locations.hierarchy({ file_group("/a/b/x.lua") })
        local folders = locations.compact(root.folders)
        assert.equals("/a/b", folders[1].name)
        assert.equals("/a/b", folders[1].path)
    end)

    it("leaves a single folder with files alone", function()
        local root = locations.hierarchy({ file_group("a/x.lua") })
        local folders = locations.compact(root.folders)
        assert.equals("a", folders[1].name)
        assert.equals(0, #folders[1].folders)
    end)
end)

describe("references.setup config", function()
    local references = require("lspnav.references")

    after_each(function()
        references.setup({})
    end)

    it("exposes its defaults without a setup call", function()
        local defaults = references.get_default_config()
        assert.is_true(defaults.include_declaration)
        assert.is_true(defaults.show_line)
        assert.equals("tree", defaults.view)
        assert.is_true(defaults.auto_expand)
        assert.is_false(defaults.indent_guides)
        assert.equals("bottom", defaults.position)
        assert.equals("float", defaults.display)
    end)

    it("merges options over the defaults", function()
        references.setup({ display = "split", position = "right", include_declaration = false })
        assert.equals("split", references.config.display)
        assert.equals("right", references.config.position)
        assert.is_false(references.config.include_declaration)
        assert.is_true(references.config.show_line)
    end)

    it("configures a window size that matches the side it opens on", function()
        references.setup({ position = "right", width_ratio = 0.3 })
        assert.equals(0.3, references.config.width_ratio)
        assert.equals(0.25, references.config.height_ratio)
    end)

    it("restores the defaults when setup runs again without them", function()
        references.setup({ position = "right" })
        references.setup({})
        assert.equals("bottom", references.config.position)
    end)

    it("keeps the config table identity across setups", function()
        local config = references.config
        references.setup({ position = "top" })
        assert.equals(config, references.config)
    end)

    it("reports being set up", function()
        references.setup({})
        assert.is_true(references.is_setup())
    end)
end)
