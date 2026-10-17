local readiness = require("lspnav.util.readiness")

--- @param pending table
--- @return table client
local function client(pending)
    return { progress = { pending = pending } }
end

describe("readiness.busy", function()
    it("is true while any progress sequence is pending", function()
        assert.is_true(readiness.busy(client({ backgroundIndexProgress = "indexing" })))
        assert.is_true(readiness.busy(client({ ["rustAnalyzer/Indexing"] = "Indexing" })))
        assert.is_true(readiness.busy(client({ ["some/server token"] = "Working" })))
    end)

    it("is false once no sequence is pending", function()
        assert.is_false(readiness.busy(client({})))
    end)

    it("is false for a client with no progress to report", function()
        assert.is_false(readiness.busy(nil))
        assert.is_false(readiness.busy({}))
    end)
end)
