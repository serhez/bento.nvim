--- Bento.nvim Actions module - Built-in action functions for buffer operations
--- This is an internal module containing action implementations.
--- Users access these via `require("bento.api").actions`
--- @module bento.actions

local M = {}

--- Built-in action: Open buffer in current window
--- @param buf_id number Buffer ID
--- @param buf_name string Buffer name/path
--- @return nil
function M.open(buf_id, buf_name)
    local bufnr = vim.fn.bufnr(buf_name)
    if bufnr ~= -1 then
        vim.cmd("buffer " .. bufnr)
    else
        vim.cmd("edit " .. buf_name)
    end
    require("bento.ui").collapse_menu()
end

--- Built-in action: Delete buffer
--- @param buf_id number Buffer ID
--- @param buf_name string Buffer name/path
--- @return nil
function M.delete(buf_id, buf_name)
    vim.api.nvim_buf_delete(buf_id, { force = false })
    require("bento.ui").refresh_menu()
end

--- Built-in action: Open buffer in vertical split
--- @param buf_id number Buffer ID
--- @param buf_name string Buffer name/path
--- @return nil
function M.vsplit(buf_id, buf_name)
    local bufnr = vim.fn.bufnr(buf_name)
    if bufnr ~= -1 then
        vim.cmd("vsplit | buffer " .. bufnr)
    else
        vim.cmd("vsplit " .. buf_name)
    end
    require("bento.ui").collapse_menu()
end

--- Built-in action: Open buffer in horizontal split
--- @param buf_id number Buffer ID
--- @param buf_name string Buffer name/path
--- @return nil
function M.split(buf_id, buf_name)
    local bufnr = vim.fn.bufnr(buf_name)
    if bufnr ~= -1 then
        vim.cmd("split | buffer " .. bufnr)
    else
        vim.cmd("split " .. buf_name)
    end
    require("bento.ui").collapse_menu()
end

--- Built-in action: Toggle lock on buffer
--- @param buf_id number Buffer ID
--- @param buf_name string Buffer name/path
--- @return nil
function M.lock(buf_id, buf_name)
    require("bento").toggle_lock(buf_id)
    require("bento.ui").refresh_menu()
end

return M
