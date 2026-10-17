-- ---------------------------------------------------------------------------
-- lspnav.util.readiness
--
-- Whether a server is still doing background work that makes its answers
-- incomplete. LSP has no standard "index is ready" signal, but the servers
-- that report such work at all do it as work-done progress, which Neovim keeps
-- in `client.progress.pending`. The tokens are server-chosen (clangd's
-- background index, rust-analyzer's indexing, gopls' workspace setup, ...), so
-- no token name can be matched generically: any pending sequence counts as
-- busy. A server that reports nothing is indistinguishable from an idle one
-- and is therefore treated as ready.
-- ---------------------------------------------------------------------------

local M = {}

--- True while any work-done progress sequence the server started is still
--- running. One caveat is inherent to reading `pending`: a server that sends
--- `begin` and never `end` looks busy until it exits.
---@param client vim.lsp.Client?
---@return boolean
function M.busy(client)
    return client ~= nil
        and client.progress ~= nil
        and next(client.progress.pending) ~= nil
end

return M
