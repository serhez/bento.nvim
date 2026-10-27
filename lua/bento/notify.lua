--- Centralized notification helper with level-based filtering.
---
--- All user-facing notifications in bento route through here so they can be
--- filtered via the `notify_level` config option. Set `notify_level` to one of
--- "debug" | "info" | "warn" | "error" to raise the threshold (e.g. "warn"
--- silences informational messages like "No buffers to display"), or `false`
--- to disable notifications entirely.

local M = {}

-- Numeric priority used for threshold comparison.
local levels = { debug = 1, info = 2, warn = 3, error = 4 }

local vim_levels = {
    debug = vim.log.levels.DEBUG,
    info = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR,
}

--- Emit a notification if it meets the configured threshold.
--- @param level "debug"|"info"|"warn"|"error"
--- @param msg string
local function notify(level, msg)
    local ok, cfg = pcall(function()
        return require("bento").get_config()
    end)
    local threshold = "info"
    if ok and cfg and cfg.notify_level ~= nil then
        threshold = cfg.notify_level
    end
    if threshold == false then
        return
    end
    if levels[level] < (levels[threshold] or levels.info) then
        return
    end
    vim.schedule(function()
        vim.notify(msg, vim_levels[level], { title = "Buffer Manager" })
    end)
end

function M.debug(msg)
    notify("debug", msg)
end

function M.info(msg)
    notify("info", msg)
end

function M.warn(msg)
    notify("warn", msg)
end

function M.error(msg)
    notify("error", msg)
end

return M
