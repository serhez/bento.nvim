--- Bento.nvim API module - Public API functions for buffer management
--- This module provides a clean public interface to bento functionality.
--- All implementations are in internal modules; this is a thin wrapper.
--- @module bento.api

local M = {}

--- Built-in action functions (exposed for use with register_action)
--- @type table<string, function>
M.actions = require("bento.actions")

--- Check if a buffer is locked
--- @param buf_id number|nil Buffer ID (defaults to current buffer)
--- @return boolean
function M.is_locked(buf_id)
    return require("bento").is_locked(buf_id)
end

--- Toggle the lock status of a buffer
--- Locked buffers are protected from automatic deletion
--- @param buf_id number|nil Buffer ID (defaults to current buffer)
--- @return boolean Whether the buffer is now locked
function M.toggle_lock(buf_id)
    return require("bento").toggle_lock(buf_id)
end

--- Close all buffers matching the specified criteria
--- By default, closes ALL buffers including visible, locked, and current buffers.
--- Pass `false` for a parameter to exclude those buffers from being closed.
---
--- @param opts table|nil Options table with the following fields:
---   - visible (boolean): If false, do not close visible buffers (default: true)
---   - locked (boolean): If false, do not close locked buffers (default: true)
---   - current (boolean): If false, do not close the current buffer (default: true)
--- @return number Number of buffers closed
function M.close_all_buffers(opts)
    return require("bento").close_all_buffers(opts)
end

--- Register a keymap to open/expand the bento menu
--- This creates a global normal-mode keymap that opens and expands the menu.
--- The key is also reserved from being used as a buffer label.
---
--- @param key string The key to register (e.g., ";")
--- @param opts table|nil Optional keymap options (passed to vim.keymap.set)
--- @return nil
function M.register_expand_key(key, opts)
    local ui = require("bento.ui")
    ui.set_registered_expand_key(key)

    opts = opts or {}
    opts.silent = opts.silent ~= false
    opts.desc = opts.desc or "Bento: Open menu"

    vim.keymap.set("n", key, function()
        ui.open_menu()
    end, opts)
end

--- Register a key to be used as the label for the last-accessed buffer
--- When registered, this key will be assigned as the label for the most recently
--- accessed buffer that is not currently visible. This allows quick switching
--- to your previous buffer by pressing the same key twice (once to open menu,
--- once to select the last buffer).
---
--- Note: This only sets the label - it does not create a global keymap.
--- The key becomes a selection keymap only when the menu is expanded.
---
--- @param key string The key to use as the last-buffer label (e.g., ";")
--- @return nil
function M.register_last_buffer_key(key)
    require("bento.ui").set_registered_last_buffer_key(key)
end

--- Get the registered expand menu key
--- @return string|nil The registered key or nil if not set
function M.get_registered_expand_key()
    return require("bento.ui").get_registered_expand_key()
end

--- Get the registered last buffer key
--- @return string|nil The registered key or nil if not set
function M.get_registered_last_buffer_key()
    return require("bento.ui").get_registered_last_buffer_key()
end

--- Register a keymap to collapse/close the bento menu (when expanded)
--- This key will only be active when the menu is expanded.
--- The key is also reserved from being used as a buffer label.
---
--- @param key string The key to register (e.g., "<Esc>")
--- @return nil
function M.register_collapse_key(key)
    local ui = require("bento.ui")
    ui.set_registered_collapse_key(key)

    -- Reserve key from being used as a buffer label
    local bento = require("bento")
    bento.line_keys = vim.tbl_filter(function(k)
        return k ~= key
    end, bento.line_keys)
end

--- Get the registered collapse key
--- @return string|nil The registered key or nil if not set
function M.get_registered_collapse_key()
    return require("bento.ui").get_registered_collapse_key()
end

--- Register a keymap for next page navigation (when expanded)
--- This key will only be active when the menu is expanded and pagination is needed.
--- The key is also reserved from being used as a buffer label.
---
--- @param key string The key to register (e.g., "]")
--- @return nil
function M.register_next_page_key(key)
    local ui = require("bento.ui")
    ui.set_registered_next_page_key(key)

    -- Reserve key from being used as a buffer label
    local bento = require("bento")
    bento.line_keys = vim.tbl_filter(function(k)
        return k ~= key
    end, bento.line_keys)
end

--- Get the registered next page key
--- @return string|nil The registered key or nil if not set
function M.get_registered_next_page_key()
    return require("bento.ui").get_registered_next_page_key()
end

--- Register a keymap for previous page navigation (when expanded)
--- This key will only be active when the menu is expanded and pagination is needed.
--- The key is also reserved from being used as a buffer label.
---
--- @param key string The key to register (e.g., "[")
--- @return nil
function M.register_prev_page_key(key)
    local ui = require("bento.ui")
    ui.set_registered_prev_page_key(key)

    -- Reserve key from being used as a buffer label
    local bento = require("bento")
    bento.line_keys = vim.tbl_filter(function(k)
        return k ~= key
    end, bento.line_keys)
end

--- Get the registered prev page key
--- @return string|nil The registered key or nil if not set
function M.get_registered_prev_page_key()
    return require("bento.ui").get_registered_prev_page_key()
end

--- Open and expand the menu
--- @return nil
function M.open_menu()
    require("bento.ui").open_menu()
end

--- Toggle menu open/closed
--- @param force_create boolean|nil If true, force create menu even without minimal mode
--- @return nil
function M.toggle_menu(force_create)
    require("bento.ui").toggle_menu(force_create)
end

--- Expand menu to show labels
--- @return nil
function M.expand_menu()
    require("bento.ui").expand_menu()
end

--- Collapse menu back to minimal state
--- @return nil
function M.collapse_menu()
    require("bento.ui").collapse_menu()
end

--- Close menu completely
--- @return nil
function M.close_menu()
    require("bento.ui").close_menu()
end

--- Refresh menu contents
--- @return nil
function M.refresh_menu()
    require("bento.ui").refresh_menu()
end

--- Select buffer by index
--- @param index number Buffer index in marks list (1-indexed)
--- @return nil
function M.select_buffer(index)
    require("bento.ui").select_buffer(index)
end

--- Go to next page (pagination)
--- @return nil
function M.next_page()
    require("bento.ui").next_page()
end

--- Go to previous page (pagination)
--- @return nil
function M.prev_page()
    require("bento.ui").prev_page()
end

--- Set action mode
--- @param action_name string Name of the action (e.g., "open", "delete", "vsplit")
--- @return nil
function M.set_action_mode(action_name)
    require("bento.ui").set_action_mode(action_name)
end

--- Set the default action (used when pressing a label key directly)
--- @param action_name string Name of the action (e.g., "open", "delete", "vsplit")
--- @return nil
function M.set_default_action(action_name)
    local bento = require("bento")
    local config = bento.get_config()
    if not config.actions[action_name] then
        vim.notify(
            "bento.nvim: Unknown action '" .. action_name .. "'",
            vim.log.levels.ERROR
        )
        return
    end
    config.default_action = action_name
end

--- Register an action
--- @param name string Name of the action (e.g., "open", "delete", "my_action")
--- @param opts table Action configuration with fields:
---   - key (string): The key to trigger this action mode
---   - action (function): Function called with (buf_id, buf_name) when buffer is selected
---   - hl (string|nil): Optional highlight group for labels in this action mode
--- @return nil
function M.register_action(name, opts)
    if not opts.key then
        vim.notify(
            "bento.nvim: Action '" .. name .. "' requires a 'key' field",
            vim.log.levels.ERROR
        )
        return
    end
    if not opts.action then
        vim.notify(
            "bento.nvim: Action '" .. name .. "' requires an 'action' field",
            vim.log.levels.ERROR
        )
        return
    end

    local bento = require("bento")
    local config = bento.get_config()

    config.actions[name] = {
        key = opts.key,
        action = opts.action,
        hl = opts.hl or config.highlights.label,
    }

    -- Reserve the action key from being used as a buffer label
    bento.line_keys = vim.tbl_filter(function(k)
        return k ~= opts.key
    end, bento.line_keys)
end

return M
