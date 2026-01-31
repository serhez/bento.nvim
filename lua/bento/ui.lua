--- Bento.nvim UI module - Handles floating window and tabline rendering
--- @module bento.ui

local bento = require("bento")
local utils = require("bento.utils")
local marks = require("bento").marks
local line_keys = require("bento").line_keys

local M = {}

--- Window ID of the bento floating window
--- @type number|nil
local bento_win_id = nil

--- Buffer handle of the bento floating window
--- @type number|nil
local bento_bufh = nil

--- Last editor window ID (non-floating window)
--- @type number|nil
local last_editor_win = nil

--- Current plugin configuration
--- @type table
local config = bento.get_config()

--- Whether the menu is in expanded state
--- @type boolean
local is_expanded = false

--- Keys we've overridden in selection mode
--- @type string[]
local selection_mode_keymaps = {}

--- Original keymaps to restore when exiting selection mode
--- @type table<string, table>
local saved_keymaps = {}

--- Currently active action mode (e.g., "open", "delete", "vsplit")
--- @type string|nil
local current_action = nil

--- Current state of minimal menu (nil | "dashed" | "filename" | "full")
--- @type string|nil
local minimal_menu_active = nil

--- Whether tabline UI is active
--- @type boolean
local tabline_active = false

--- Original tabline setting
--- @type string|nil
local saved_tabline = nil

--- Original showtabline setting
--- @type number|nil
local saved_showtabline = nil

--- Cache for smart labels used by tabline
--- @type table<number, string>
local smart_labels_cache = {}

--- First buffer index to display in tabline (1-indexed)
--- @type number
local tabline_start_idx = 1

--- Last buffer index displayed in tabline (1-indexed)
--- @type number
local tabline_end_idx = 1

--- Current page for floating UI pagination (1-indexed)
--- @type number
local current_page = 1

--- Registered key for expanding the menu (set via register_expand_key)
--- @type string|nil
local registered_expand_key = nil

--- Registered key for the last-accessed buffer (set via register_last_buffer_key)
--- @type string|nil
local registered_last_buffer_key = nil

--- Registered key for collapsing/closing the menu (set via register_collapse_key)
--- @type string|nil
local registered_collapse_key = nil

--- Registered key for next page (set via register_next_page_key)
--- @type string|nil
local registered_next_page_key = nil

--- Registered key for previous page (set via register_prev_page_key)
--- @type string|nil
local registered_prev_page_key = nil

--- Track which warnings have been shown to avoid repetition
--- @type table<string, boolean>
local warnings_shown = {}

--- Show a warning once per session
--- @param key string Unique key for this warning
--- @param message string Warning message to display
--- @return nil
local function warn_once(key, message)
    if warnings_shown[key] then
        return
    end
    warnings_shown[key] = true
    vim.notify(message, vim.log.levels.WARN, { title = "Buffer Manager" })
end

--- Initialize UI state from configuration
--- @return nil
function M.setup_state()
    config = bento.get_config()
    if config.ui.mode == "tabline" then
        return
    end
    if minimal_menu_active == nil then
        minimal_menu_active = config.ui.floating.minimal_menu
    end
end

--- Set the last editor window ID
--- @param win_id number Window ID
--- @return nil
function M.set_last_editor_win(win_id)
    last_editor_win = win_id
end

vim.api.nvim_set_hl(0, "BentoNormal", { bg = "NONE", fg = "NONE" })

--- Check if using tabline UI mode
--- @return boolean
local function is_tabline_ui()
    config = bento.get_config()
    return config.ui.mode == "tabline"
end

--- Check if buffer is visible in current tab
--- @param buf_id number Buffer ID
--- @return boolean
local function is_buffer_visible_in_tab(buf_id)
    for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if
            vim.api.nvim_win_is_valid(win_id)
            and vim.api.nvim_win_get_buf(win_id) == buf_id
        then
            return true
        end
    end
    return false
end

--- Get the last accessed buffer not currently visible
--- @return number|nil Buffer ID or nil if none found
local function get_last_accessed_buffer()
    local sorted_buffers = {}
    for _, mark in ipairs(marks) do
        if vim.api.nvim_buf_is_valid(mark.buf_id) then
            local buf_info = vim.fn.getbufinfo(mark.buf_id)[1]
            if buf_info then
                table.insert(
                    sorted_buffers,
                    { buf_id = mark.buf_id, lastused = buf_info.lastused }
                )
            end
        end
    end

    table.sort(sorted_buffers, function(a, b)
        return a.lastused > b.lastused
    end)

    for _, buf_info in ipairs(sorted_buffers) do
        if not is_buffer_visible_in_tab(buf_info.buf_id) then
            return buf_info.buf_id
        end
    end
    return nil
end

--- Get the index of a buffer in the marks list
--- @param buf_id number Buffer ID
--- @return number|nil Index (1-indexed) or nil if not found
local function get_buffer_index(buf_id)
    for i, mark in ipairs(marks) do
        if mark.buf_id == buf_id then
            return i
        end
    end
    return nil
end

--- Find main content window (non-floating)
--- @return number Window ID
local function find_main_window()
    local current_win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_config(current_win).relative == "" then
        return current_win
    end
    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win_id).relative == "" then
            return win_id
        end
    end
    return current_win
end

--- Update marks (buffer list) by removing invalid buffers and adding new ones
--- @return nil
local function update_marks()
    -- Remove invalid buffers
    for idx = #marks, 1, -1 do
        if
            not utils.buffer_is_valid(marks[idx].buf_id, marks[idx].filename)
        then
            table.remove(marks, idx)
        end
    end

    -- Add new buffers
    for _, buf in pairs(vim.api.nvim_list_bufs()) do
        local bufname = vim.api.nvim_buf_get_name(buf)
        if utils.buffer_is_valid(buf, bufname) then
            local found = false
            for _, mark in ipairs(marks) do
                if mark.buf_id == buf then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(marks, { filename = bufname, buf_id = buf })
            end
        end
    end

    config = bento.get_config()
    if config.ordering_metric then
        table.sort(marks, function(a, b)
            local a_val = bento.get_ordering_value(a.buf_id)
            local b_val = bento.get_ordering_value(b.buf_id)
            if a_val == b_val then
                return a.buf_id < b.buf_id
            end
            return a_val > b_val
        end)
    end
end

--- Get pagination info for floating UI
--- @return number max_per_page Maximum buffers per page
--- @return number total_pages Total number of pages
--- @return boolean needs_pagination Whether pagination is needed
local function get_pagination_info()
    local max_rendered = config.ui.floating.max_rendered_buffers

    local ui = vim.api.nvim_list_uis()[1]
    local screen_height = ui and ui.height or 24
    local available_height = screen_height - 3

    local effective_max
    if max_rendered and max_rendered > 0 then
        effective_max = math.min(max_rendered, available_height)
    else
        effective_max = available_height
    end

    if effective_max < 1 then
        effective_max = 1
    end

    if #marks <= effective_max then
        return #marks, 1, false
    end

    local total_pages = math.ceil(#marks / effective_max)
    return effective_max, total_pages, true
end

--- Get the slice of marks for the current page
--- @return table[] visible_marks List of marks for current page
--- @return number start_index Starting index (1-indexed)
local function get_page_marks()
    local max_per_page, total_pages, needs_pagination = get_pagination_info()
    if not needs_pagination then
        return marks, 1
    end
    if current_page < 1 then
        current_page = 1
    elseif current_page > total_pages then
        current_page = total_pages
    end
    local start_idx = (current_page - 1) * max_per_page + 1
    local end_idx = math.min(start_idx + max_per_page - 1, #marks)
    local visible_marks = {}
    for i = start_idx, end_idx do
        table.insert(visible_marks, marks[i])
    end
    return visible_marks, start_idx
end

--- Generate pagination indicator string
--- @param width number Total width for the indicator
--- @return string|nil Formatted indicator string or nil if no pagination needed
local function generate_pagination_indicator(width)
    local _, total_pages, needs_pagination = get_pagination_info()
    if not needs_pagination then
        return nil
    end
    local dots = {}
    for i = 1, total_pages do
        if i == current_page then
            table.insert(dots, "●")
        else
            table.insert(dots, "○")
        end
    end
    local indicator = table.concat(dots, " ")
    local indicator_width = vim.fn.strwidth(indicator)
    local padding = math.floor((width - indicator_width) / 2)
    if padding < 0 then
        padding = 0
    end
    return string.rep(" ", padding)
        .. indicator
        .. string.rep(" ", width - padding - indicator_width)
end

--- Get available keys for label assignment (filters out registered keys)
--- @return string[]
local function get_available_keys()
    local available = {}
    for _, key in ipairs(line_keys) do
        if
            key ~= registered_expand_key
            and key ~= registered_last_buffer_key
        then
            table.insert(available, key)
        end
    end
    return available
end

--- Assign smart labels to buffers
--- @param buffers table[] List of buffer marks
--- @param available_keys string[] List of available keys for labels
--- @return table<number, string> Mapping of buffer index to label
local function assign_smart_labels(buffers, available_keys)
    local label_assignment = {}
    local used_labels = {}
    local last_accessed_buf = get_last_accessed_buffer()

    if
        registered_last_buffer_key
        and not config.map_last_accessed
        and last_accessed_buf
    then
        for i, mark in ipairs(buffers) do
            if mark.buf_id == last_accessed_buf then
                label_assignment[i] = registered_last_buffer_key
                used_labels[registered_last_buffer_key] = true
                break
            end
        end
    end

    local char_to_buffers = {}
    for i, mark in ipairs(buffers) do
        if not label_assignment[i] then
            local filename = utils.get_file_name(mark.filename)
            local first_alnum = filename:match("[%w]")
            if first_alnum then
                local char_lower = string.lower(first_alnum)
                if not char_to_buffers[char_lower] then
                    char_to_buffers[char_lower] = {}
                end
                table.insert(char_to_buffers[char_lower], i)
            end
        end
    end

    -- Assign labels to files uniquely identified by their first character
    -- Try lowercase first, then uppercase
    for char, buffer_indices in pairs(char_to_buffers) do
        if #buffer_indices == 1 then
            local i = buffer_indices[1]
            local key_lower = string.lower(char)
            local key_upper = string.upper(char)

            if
                vim.tbl_contains(available_keys, key_lower)
                and not used_labels[key_lower]
            then
                label_assignment[i] = key_lower
                used_labels[key_lower] = true
            elseif
                vim.tbl_contains(available_keys, key_upper)
                and not used_labels[key_upper]
            then
                label_assignment[i] = key_upper
                used_labels[key_upper] = true
            end
        end
    end

    -- For files sharing the same first char
    -- Also try lowercase first, then uppercase
    for char, buffer_indices in pairs(char_to_buffers) do
        if #buffer_indices > 1 then
            local key_lower = string.lower(char)
            local key_upper = string.upper(char)

            for _, i in ipairs(buffer_indices) do
                if not label_assignment[i] then
                    if
                        vim.tbl_contains(available_keys, key_lower)
                        and not used_labels[key_lower]
                    then
                        label_assignment[i] = key_lower
                        used_labels[key_lower] = true
                    elseif
                        vim.tbl_contains(available_keys, key_upper)
                        and not used_labels[key_upper]
                    then
                        label_assignment[i] = key_upper
                        used_labels[key_upper] = true
                    end
                end
            end
        end
    end

    -- Fill remaining buffers with single-character available keys
    local key_idx = 1
    for i = 1, #buffers do
        if not label_assignment[i] then
            while
                key_idx <= #available_keys
                and used_labels[available_keys[key_idx]]
            do
                key_idx = key_idx + 1
            end
            if key_idx <= #available_keys then
                label_assignment[i] = available_keys[key_idx]
                used_labels[available_keys[key_idx]] = true
                key_idx = key_idx + 1
            else
                break
            end
        end
    end

    -- If we run out of single-character keys, generate multi-character
    -- labels for remaining buffers
    if #buffers > #available_keys then
        local multi_char_idx = 1
        for i = 1, #buffers do
            if not label_assignment[i] then
                local label
                repeat
                    local first_idx = math.floor(
                        (multi_char_idx - 1) / #available_keys
                    ) + 1
                    local second_idx = ((multi_char_idx - 1) % #available_keys)
                        + 1
                    label = available_keys[first_idx]
                        .. available_keys[second_idx]
                    multi_char_idx = multi_char_idx + 1
                until not used_labels[label]

                label_assignment[i] = label
                used_labels[label] = true
            end
        end
    end

    return label_assignment
end

--- Calculate window position based on config.ui.floating.position
--- Supports: "top-left", "top-right", "middle-left", "middle-right", "bottom-left", "bottom-right"
--- @param height number Window height
--- @param width number Window width
--- @return number row Row position
--- @return number col Column position
local function calculate_position(height, width)
    local ui = vim.api.nvim_list_uis()[1]
    local floating = config.ui.floating
    local position = floating.position or "middle-right"
    local offset_x = floating.offset_x or 0
    local offset_y = floating.offset_y or 0

    local row, col

    -- Vertical positioning
    if position:match("^top") then
        row = 0
    elseif position:match("^bottom") then
        row = ui.height - height
    else
        row = math.floor((ui.height - height) / 2)
    end

    -- Horizontal positioning
    if position:match("left$") then
        col = 0
    else
        col = ui.width - width + 1
    end

    return row + offset_y, col + offset_x
end

--- Create a transparent floating window
--- @param height number Window height
--- @param width number Window width
--- @return {bufnr: number, win_id: number}
local function create_window(height, width)
    local row, col = calculate_position(height, width)

    local bufnr = vim.api.nvim_create_buf(false, true)
    local win_id = vim.api.nvim_open_win(bufnr, false, {
        relative = "editor",
        style = "minimal",
        width = width,
        height = height,
        row = row,
        col = col,
        border = config.ui.floating.border or "none",
        focusable = false,
    })

    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
    vim.api.nvim_win_set_option(win_id, "wrap", false)
    vim.api.nvim_win_set_option(win_id, "winblend", 0)
    vim.api.nvim_win_set_option(
        win_id,
        "winhighlight",
        "Normal:" .. config.highlights.window_bg
    )

    return { bufnr = bufnr, win_id = win_id }
end

--- Update window size dynamically
--- @param width number New width
--- @param height number New height
--- @return nil
local function update_window_size(width, height)
    if not bento_win_id or not vim.api.nvim_win_is_valid(bento_win_id) then
        return
    end

    local row, col = calculate_position(height, width)

    pcall(vim.api.nvim_win_set_config, bento_win_id, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
    })
end

--- Check if buffer is active (visible in any window)
--- @param buf_id number Buffer ID
--- @return boolean
local function is_buffer_active(buf_id)
    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
        if
            vim.api.nvim_win_is_valid(win_id)
            and vim.api.nvim_win_get_buf(win_id) == buf_id
        then
            return true
        end
    end
    return false
end

--- Check if buffer is the current buffer in the last editor window
--- @param buf_id number Buffer ID
--- @return boolean
local function is_current_buffer(buf_id)
    return last_editor_win
        and vim.api.nvim_win_is_valid(last_editor_win)
        and vim.api.nvim_win_get_buf(last_editor_win) == buf_id
end

--- Generate dash line for a buffer
--- @param buf_id number Buffer ID
--- @return string Dash line string
local function generate_dash_line(buf_id)
    local dash_char = config.ui.floating.dash_char
    return is_current_buffer(buf_id) and (dash_char:rep(2))
        or (" " .. dash_char)
end

--- Save original keymap before overriding
--- @param mode string Vim mode (e.g., "n")
--- @param key string Key to save
--- @return nil
local function save_keymap(mode, key)
    local normalized_key = vim.api.nvim_replace_termcodes(key, true, true, true)

    local keymaps = vim.api.nvim_get_keymap(mode)
    for _, map in ipairs(keymaps) do
        local map_lhs =
            vim.api.nvim_replace_termcodes(map.lhs, true, true, true)
        if map_lhs == normalized_key then
            saved_keymaps[key] = {
                lhs = map.lhs,
                rhs = map.rhs,
                callback = map.callback,
                expr = map.expr == 1,
                noremap = map.noremap == 1,
                silent = map.silent == 1,
                nowait = map.nowait == 1,
                script = map.script == 1,
                buffer = map.buffer,
                desc = map.desc,
            }
            return
        end
    end
    saved_keymaps[key] = nil
end

--- Restore original keymap
--- @param mode string Vim mode (e.g., "n")
--- @param key string Key to restore
--- @return nil
local function restore_keymap(mode, key)
    local original = saved_keymaps[key]

    pcall(vim.keymap.del, mode, key)

    if original then
        local opts = {
            noremap = original.noremap,
            silent = original.silent,
            expr = original.expr,
            nowait = original.nowait,
            script = original.script,
            desc = original.desc,
        }

        if original.callback then
            vim.keymap.set(mode, key, original.callback, opts)
        elseif original.rhs then
            if original.noremap then
                vim.api.nvim_set_keymap(mode, original.lhs, original.rhs, opts)
            else
                opts.remap = true
                vim.keymap.set(mode, original.lhs, original.rhs, opts)
            end
        end
    end

    saved_keymaps[key] = nil
end

--- Clear all selection mode keymaps and restore originals
--- @return nil
local function clear_selection_keymaps()
    for _, key in ipairs(selection_mode_keymaps) do
        restore_keymap("n", key)
    end
    selection_mode_keymaps = {}
end

--- Set global keybindings for selection mode
--- @param smart_labels table<number, string> Mapping of buffer index to label
--- @return nil
local function set_selection_keybindings(smart_labels)
    clear_selection_keymaps()

    local last_accessed_buf = get_last_accessed_buffer()
    local last_accessed_idx = nil

    for i, label in pairs(smart_labels) do
        local mark = marks[i]
        if mark and mark.buf_id == last_accessed_buf then
            last_accessed_idx = i
        end

        -- Skip empty labels
        local is_expand_key = label == registered_expand_key
        local is_last_buffer_label = label == registered_last_buffer_key
        local should_skip = not label
            or label == " "
            or (is_expand_key and not is_last_buffer_label)

        if not should_skip then
            save_keymap("n", label)
            vim.keymap.set("n", label, function()
                require("bento.ui").select_buffer(i)
            end, {
                silent = true,
                desc = "Bento: Select buffer " .. i,
            })
            table.insert(selection_mode_keymaps, label)
        end
    end

    if
        registered_last_buffer_key
        and config.map_last_accessed
        and last_accessed_idx
        and not vim.tbl_contains(
            selection_mode_keymaps,
            registered_last_buffer_key
        )
    then
        save_keymap("n", registered_last_buffer_key)
        vim.keymap.set("n", registered_last_buffer_key, function()
            require("bento.ui").select_buffer(last_accessed_idx)
        end, {
            silent = true,
            desc = "Bento: Select last-accessed buffer",
        })
        table.insert(selection_mode_keymaps, registered_last_buffer_key)
    end

    for action_name, action_config in pairs(config.actions) do
        if action_config.key then
            save_keymap("n", action_config.key)
            vim.keymap.set("n", action_config.key, function()
                require("bento.ui").set_action_mode(action_name)
            end, {
                silent = true,
                desc = "Bento: " .. action_name .. " mode",
            })
            table.insert(selection_mode_keymaps, action_config.key)
        end
    end

    local _, _, needs_floating_pagination = get_pagination_info()
    local needs_tabline_pagination = is_tabline_ui() and #marks > 0
    if needs_floating_pagination or needs_tabline_pagination then
        if registered_prev_page_key then
            save_keymap("n", registered_prev_page_key)
            vim.keymap.set("n", registered_prev_page_key, function()
                require("bento.ui").prev_page()
            end, { silent = true, desc = "Bento: Previous page" })
            table.insert(selection_mode_keymaps, registered_prev_page_key)
        end

        if registered_next_page_key then
            save_keymap("n", registered_next_page_key)
            vim.keymap.set("n", registered_next_page_key, function()
                require("bento.ui").next_page()
            end, { silent = true, desc = "Bento: Next page" })
            table.insert(selection_mode_keymaps, registered_next_page_key)
        end
    end

    if registered_collapse_key then
        save_keymap("n", registered_collapse_key)
        vim.keymap.set("n", registered_collapse_key, function()
            require("bento.ui").collapse_menu()
        end, { silent = true, desc = "Bento: Collapse menu" })
        table.insert(selection_mode_keymaps, registered_collapse_key)
    end
end

--- Display menu in dashed collapsed state
--- @return nil
local function render_dashed()
    if not bento_bufh or not vim.api.nvim_buf_is_valid(bento_bufh) then
        return
    end

    config = bento.get_config()
    update_marks()
    local visible_marks, _ = get_page_marks()
    local _, _, needs_pagination = get_pagination_info()
    local contents = {}
    local padding = config.ui.floating.label_padding or 1
    local padding_str = string.rep(" ", padding)

    for i = 1, #visible_marks do
        contents[i] = padding_str
            .. generate_dash_line(visible_marks[i].buf_id)
            .. padding_str
    end

    local dash_width = vim.fn.strwidth(
        generate_dash_line(visible_marks[1] and visible_marks[1].buf_id or 0)
    )
    local total_width = dash_width + 2 * padding
    local total_height = #visible_marks

    if needs_pagination then
        -- Add empty line to maintain alignment with expanded mode
        -- (don't show indicator dots in dashed mode)
        table.insert(contents, string.rep(" ", total_width))
        total_height = total_height + 1
    end

    vim.api.nvim_buf_set_option(bento_bufh, "modifiable", true)
    vim.api.nvim_buf_set_lines(bento_bufh, 0, -1, false, contents)
    vim.api.nvim_buf_set_option(bento_bufh, "modifiable", false)

    update_window_size(total_width, total_height)

    local ns_id = vim.api.nvim_create_namespace("BentoDash")
    vim.api.nvim_buf_clear_namespace(bento_bufh, ns_id, 0, -1)

    for i, mark in ipairs(visible_marks) do
        local is_modified = vim.api.nvim_buf_get_option(mark.buf_id, "modified")
        if is_modified then
            vim.api.nvim_buf_add_highlight(
                bento_bufh,
                ns_id,
                config.highlights.modified,
                i - 1,
                0,
                -1
            )
        elseif not is_buffer_active(mark.buf_id) then
            vim.api.nvim_buf_add_highlight(
                bento_bufh,
                ns_id,
                config.highlights.inactive_dash,
                i - 1,
                0,
                -1
            )
        end
    end

    clear_selection_keymaps()
end

--- Display menu in filename-only collapsed state
--- @return nil
local function render_filename_collapsed()
    if not bento_bufh or not vim.api.nvim_buf_is_valid(bento_bufh) then
        return
    end

    config = bento.get_config()
    update_marks()
    local visible_marks, start_idx = get_page_marks()
    local _, _, needs_pagination = get_pagination_info()
    local contents = {}
    local padding = config.ui.floating.label_padding or 1
    local padding_str = string.rep(" ", padding)
    local lock_char = config.lock_char or "🔒"

    local all_paths = {}
    for _, mark in ipairs(marks) do
        table.insert(all_paths, mark.filename)
    end
    local display_names = utils.get_display_names(all_paths)

    local max_content_width = 0
    local all_line_data = {}
    for _, mark in ipairs(marks) do
        local display_name = display_names[mark.filename]
            or utils.get_file_name(mark.filename)
        local is_locked = bento.is_locked(mark.buf_id)
        local lock_prefix = is_locked and (lock_char .. " ") or ""
        local content_width = vim.fn.strwidth(lock_prefix .. display_name)
        max_content_width = math.max(max_content_width, content_width)
        table.insert(all_line_data, {
            display_name = display_name,
            lock_prefix = lock_prefix,
            is_locked = is_locked,
            content_width = content_width,
        })
    end

    local line_data = {}
    for i = start_idx, start_idx + #visible_marks - 1 do
        table.insert(line_data, all_line_data[i])
    end

    local total_width = padding + max_content_width + padding
    local total_height = #visible_marks

    for i, data in ipairs(line_data) do
        local left_space = max_content_width - data.content_width
        local line = padding_str
            .. string.rep(" ", left_space)
            .. data.lock_prefix
            .. data.display_name
            .. padding_str
        contents[i] = line
    end

    if needs_pagination then
        local indicator = generate_pagination_indicator(total_width)
        if indicator then
            table.insert(contents, indicator)
            total_height = total_height + 1
        end
    end

    vim.api.nvim_buf_set_option(bento_bufh, "modifiable", true)
    vim.api.nvim_buf_set_lines(bento_bufh, 0, -1, false, contents)
    vim.api.nvim_buf_set_option(bento_bufh, "modifiable", false)

    update_window_size(total_width, total_height)

    local ns_id = vim.api.nvim_create_namespace("BentoFilename")
    vim.api.nvim_buf_clear_namespace(bento_bufh, ns_id, 0, -1)

    for i, mark in ipairs(visible_marks) do
        local is_current = is_current_buffer(mark.buf_id)
        local is_active = is_buffer_active(mark.buf_id)
        local is_modified = vim.api.nvim_buf_get_option(mark.buf_id, "modified")
        local data = line_data[i]

        local left_space = max_content_width - data.content_width
        local lock_prefix_bytes = #data.lock_prefix
        local display_name_bytes = #data.display_name
        local display_name_start = padding + left_space + lock_prefix_bytes
        local display_name_end = display_name_start + display_name_bytes

        local filename_hl
        if is_modified then
            filename_hl = config.highlights.modified
        elseif is_current then
            filename_hl = config.highlights.current
        elseif is_active then
            filename_hl = config.highlights.active
        else
            filename_hl = config.highlights.inactive
        end

        if is_modified then
            vim.api.nvim_buf_add_highlight(
                bento_bufh,
                ns_id,
                filename_hl,
                i - 1,
                0,
                -1
            )
        else
            vim.api.nvim_buf_add_highlight(
                bento_bufh,
                ns_id,
                filename_hl,
                i - 1,
                display_name_start,
                display_name_end
            )
        end
    end

    if needs_pagination then
        vim.api.nvim_buf_add_highlight(
            bento_bufh,
            ns_id,
            config.highlights.page_indicator,
            #visible_marks,
            0,
            -1
        )
    end

    clear_selection_keymaps()
end

--- Display menu in expanded state (labels + names)
--- @param is_minimal_full boolean|nil If true, uses minimal highlight for labels
--- @return nil
local function render_expanded(is_minimal_full)
    if not bento_bufh or not vim.api.nvim_buf_is_valid(bento_bufh) then
        return
    end

    config = bento.get_config()
    update_marks()
    local smart_labels = assign_smart_labels(marks, get_available_keys())
    local visible_marks, start_idx = get_page_marks()
    local _, _, needs_pagination = get_pagination_info()
    local contents = {}
    local padding = config.ui.floating.label_padding or 1
    local padding_str = string.rep(" ", padding)
    local lock_char = config.lock_char or "🔒"

    local all_paths = {}
    for _, mark in ipairs(marks) do
        table.insert(all_paths, mark.filename)
    end
    local display_names = utils.get_display_names(all_paths)

    local max_content_width = 0
    local all_line_data = {}
    for i, mark in ipairs(marks) do
        local label = smart_labels[i] or " "
        local display_name = display_names[mark.filename]
            or utils.get_file_name(mark.filename)
        local is_locked = bento.is_locked(mark.buf_id)
        local lock_prefix = is_locked and (lock_char .. " ") or ""
        -- Format: [lock_prefix][display_name] [space] [padding][label][padding]
        local content_width = vim.fn.strwidth(lock_prefix)
            + vim.fn.strwidth(display_name)
            + 1
            + padding
            + #label
            + padding
        max_content_width = math.max(max_content_width, content_width)
        table.insert(all_line_data, {
            label = label,
            display_name = display_name,
            lock_prefix = lock_prefix,
            is_locked = is_locked,
            content_width = content_width,
            global_idx = i,
        })
    end

    local line_data = {}
    for i = start_idx, start_idx + #visible_marks - 1 do
        table.insert(line_data, all_line_data[i])
    end

    local total_width = padding + max_content_width
    local total_height = #visible_marks

    for i, data in ipairs(line_data) do
        local left_space = max_content_width - data.content_width
        -- Format: [padding][left_space][lock_prefix][display_name] [space] [padding][label][padding]
        local line = padding_str
            .. string.rep(" ", left_space)
            .. data.lock_prefix
            .. data.display_name
            .. " "
            .. padding_str
            .. data.label
            .. padding_str
        contents[i] = line
    end

    if needs_pagination then
        local indicator = generate_pagination_indicator(total_width)
        if indicator then
            table.insert(contents, indicator)
            total_height = total_height + 1
        end
    end

    vim.api.nvim_buf_set_option(bento_bufh, "modifiable", true)
    vim.api.nvim_buf_set_lines(bento_bufh, 0, -1, false, contents)
    vim.api.nvim_buf_set_option(bento_bufh, "modifiable", false)

    update_window_size(total_width, total_height)

    local ns_id = vim.api.nvim_create_namespace("BentoLabel")
    vim.api.nvim_buf_clear_namespace(bento_bufh, ns_id, 0, -1)

    local last_accessed_buf = get_last_accessed_buffer()
    for i, mark in ipairs(visible_marks) do
        local data = line_data[i]
        local label = data.label
        local is_current = is_current_buffer(mark.buf_id)
        local is_active = is_buffer_active(mark.buf_id)
        local is_modified = vim.api.nvim_buf_get_option(mark.buf_id, "modified")

        if label and label ~= " " then
            local left_space = max_content_width - data.content_width
            local lock_prefix_bytes = #data.lock_prefix
            local display_name_bytes = #data.display_name
            local display_name_start = padding + left_space + lock_prefix_bytes
            local display_name_end = display_name_start + display_name_bytes
            local label_start = display_name_end + 1 + padding
            local label_end = label_start + #label + padding

            local label_hl
            local is_previous_buffer = mark.buf_id == last_accessed_buf
            if is_minimal_full then
                label_hl = config.highlights.label_minimal
            elseif is_previous_buffer then
                label_hl = config.highlights.previous
            else
                local action_name = current_action
                    or config.default_action
                    or "open"
                label_hl = config.highlights.label

                if
                    config.actions[action_name]
                    and config.actions[action_name].hl
                then
                    label_hl = config.actions[action_name].hl
                end
            end

            local filename_hl
            if is_modified then
                filename_hl = config.highlights.modified
            elseif is_current then
                filename_hl = config.highlights.current
            elseif is_active then
                filename_hl = config.highlights.active
            else
                filename_hl = config.highlights.inactive
            end

            if is_modified then
                vim.api.nvim_buf_add_highlight(
                    bento_bufh,
                    ns_id,
                    filename_hl,
                    i - 1,
                    0,
                    display_name_end + 1
                )
            else
                vim.api.nvim_buf_add_highlight(
                    bento_bufh,
                    ns_id,
                    filename_hl,
                    i - 1,
                    display_name_start,
                    display_name_end
                )
            end

            vim.api.nvim_buf_add_highlight(
                bento_bufh,
                ns_id,
                label_hl,
                i - 1,
                label_start - padding,
                label_end
            )
        end
    end

    if needs_pagination then
        vim.api.nvim_buf_add_highlight(
            bento_bufh,
            ns_id,
            config.highlights.page_indicator,
            #visible_marks,
            0,
            -1
        )
    end

    if is_minimal_full then
        clear_selection_keymaps()
    else
        set_selection_keybindings(smart_labels)
    end
end

--- Calculate segment widths for all marks (used for tabline pagination)
--- @return number[] Array of widths for each mark
local function get_tabline_segment_widths()
    config = bento.get_config()
    local smart_labels = assign_smart_labels(marks, get_available_keys())
    local lock_char = config.lock_char or "🔒"

    local all_paths = {}
    for _, mark in ipairs(marks) do
        table.insert(all_paths, mark.filename)
    end
    local display_names = utils.get_display_names(all_paths)

    local widths = {}
    for i, mark in ipairs(marks) do
        local label = smart_labels[i] or " "
        local display_name = display_names[mark.filename]
            or utils.get_file_name(mark.filename)
        local is_locked = bento.is_locked(mark.buf_id)

        local width = 0
        if label and label ~= " " then
            width = width + 1 + vim.fn.strwidth(label) + 1
        end
        if is_locked then
            width = width + 1 + vim.fn.strwidth(lock_char)
        end
        width = width + 1 + vim.fn.strwidth(display_name)

        table.insert(widths, width)
    end

    return widths
end

--- Calculate the start index for the previous page in tabline
--- @param current_start_idx number Current starting index
--- @return number Start index for previous page
local function get_tabline_prev_page_start(current_start_idx)
    if current_start_idx <= 1 then
        return 1
    end

    config = bento.get_config()
    local ui = vim.api.nvim_list_uis()[1]
    local screen_width = ui and ui.width or 80
    local separator_symbol = config.ui.tabline.separator_symbol or "|"
    local separator_width = 1 + vim.fn.strwidth(separator_symbol) + 1 -- " symbol " between segments
    local left_symbol = config.ui.tabline.left_page_symbol or "❮"
    local right_symbol = config.ui.tabline.right_page_symbol or "❯"
    local left_symbol_width = vim.fn.strwidth(left_symbol)
    local right_symbol_width = vim.fn.strwidth(right_symbol)
    local left_symbol_with_spacing = 1 + left_symbol_width + 2 -- 1-space margin + symbol + 2-space gap
    local right_symbol_with_spacing = 2 + right_symbol_width + 1 -- 2-space gap + symbol + 1-space margin

    local widths = get_tabline_segment_widths()

    local target_end_idx = current_start_idx - 1

    local available_width = screen_width - right_symbol_with_spacing -- reserve for trailing symbol + gap

    local total_width = 0
    local start_idx = target_end_idx

    for i = target_end_idx, 1, -1 do
        local seg_width = widths[i]
        local needed_width = seg_width
        if i < target_end_idx then
            needed_width = needed_width + separator_width
        end

        local has_prev = i > 1
        local test_available = available_width
        if has_prev then
            test_available = test_available - left_symbol_with_spacing
        end

        if total_width + needed_width <= test_available then
            total_width = total_width + needed_width
            start_idx = i
        else
            break
        end
    end

    return start_idx
end

--- Generate the tabline string for rendering
--- @param is_minimal boolean If true, uses minimal highlight for labels
--- @return string tabline_string The formatted tabline string
--- @return number end_idx Last visible buffer index
local function generate_tabline_string(is_minimal)
    config = bento.get_config()
    update_marks()

    if #marks == 0 then
        return ""
    end

    local smart_labels = assign_smart_labels(marks, get_available_keys())
    smart_labels_cache = smart_labels
    local lock_char = config.lock_char or "🔒"
    local window_bg_hl = config.highlights.window_bg
    local page_indicator_hl = config.highlights.page_indicator

    local all_paths = {}
    for _, mark in ipairs(marks) do
        table.insert(all_paths, mark.filename)
    end
    local display_names = utils.get_display_names(all_paths)

    -- Creates a tabline-specific highlight group with window_bg background
    local function get_tabline_hl(base_hl)
        local tabline_hl_name = "BentoTabline_" .. base_hl
        local base_hl_info =
            vim.api.nvim_get_hl(0, { name = base_hl, link = false })
        local fg = base_hl_info.fg
        local bg_hl_info =
            vim.api.nvim_get_hl(0, { name = window_bg_hl, link = false })
        vim.api.nvim_set_hl(0, tabline_hl_name, {
            fg = fg,
            bg = bg_hl_info.bg,
            bold = base_hl_info.bold,
            italic = base_hl_info.italic,
            underline = base_hl_info.underline,
        })
        return tabline_hl_name
    end

    local tabline_page_indicator_hl = get_tabline_hl(page_indicator_hl)

    local separator_hl = config.highlights.separator or "Normal"
    local tabline_separator_hl = get_tabline_hl(separator_hl)
    local separator_symbol = config.ui.tabline.separator_symbol or "|"

    -- Calculates the display width of a buffer segment
    local function get_segment_width(label, display_name, is_locked)
        local width = 0
        if label and label ~= " " then
            width = width + 1 + vim.fn.strwidth(label) + 1
        end
        if is_locked then
            width = width + 1 + vim.fn.strwidth(lock_char)
        end
        width = width + 1 + vim.fn.strwidth(display_name)
        return width
    end

    local last_accessed_buf = get_last_accessed_buffer()
    local all_segments = {}
    for i, mark in ipairs(marks) do
        local label = smart_labels[i] or " "
        local display_name = display_names[mark.filename]
            or utils.get_file_name(mark.filename)
        local is_locked = bento.is_locked(mark.buf_id)
        local is_current = is_current_buffer(mark.buf_id)
        local is_active = is_buffer_active(mark.buf_id)
        local is_modified = vim.api.nvim_buf_get_option(mark.buf_id, "modified")

        local label_hl
        local is_previous_buffer = mark.buf_id == last_accessed_buf
        if is_minimal then
            label_hl = config.highlights.label_minimal
        elseif is_previous_buffer then
            label_hl = config.highlights.previous
        else
            local action_name = current_action
                or config.default_action
                or "open"
            label_hl = config.highlights.label
            if
                config.actions[action_name] and config.actions[action_name].hl
            then
                label_hl = config.actions[action_name].hl
            end
        end

        local filename_hl
        if is_modified then
            filename_hl = config.highlights.modified
        elseif is_current then
            filename_hl = config.highlights.current
        elseif is_active then
            filename_hl = config.highlights.active
        else
            filename_hl = config.highlights.inactive
        end

        local tabline_filename_hl = get_tabline_hl(filename_hl)

        local segment = ""
        if label and label ~= " " then
            segment = segment .. "%#" .. label_hl .. "#" .. " " .. label .. " "
        end
        if is_locked then
            segment = segment
                .. "%#"
                .. tabline_filename_hl
                .. "#"
                .. " "
                .. lock_char
        end
        segment = segment
            .. "%#"
            .. tabline_filename_hl
            .. "#"
            .. " "
            .. display_name

        table.insert(all_segments, {
            segment = segment,
            width = get_segment_width(label, display_name, is_locked),
        })
    end

    local ui = vim.api.nvim_list_uis()[1]
    local screen_width = ui and ui.width or 80
    local separator_width = 1 + vim.fn.strwidth(separator_symbol) + 1 -- " symbol " between segments
    local left_symbol = config.ui.tabline.left_page_symbol or "❮"
    local right_symbol = config.ui.tabline.right_page_symbol or "❯"
    local left_symbol_width = vim.fn.strwidth(left_symbol)
    local right_symbol_width = vim.fn.strwidth(right_symbol)
    local left_symbol_with_spacing = 1 + left_symbol_width + 2 -- 1-space margin + symbol + 2-space gap
    local right_symbol_with_spacing = 2 + right_symbol_width + 1 -- 2-space gap + symbol + 1-space margin

    if tabline_start_idx < 1 then
        tabline_start_idx = 1
    elseif tabline_start_idx > #marks then
        tabline_start_idx = #marks
    end

    local has_prev = tabline_start_idx > 1
    local available_width = screen_width
    if has_prev then
        available_width = available_width - left_symbol_with_spacing
    end

    local visible_segments = {}
    local current_width = 0
    local end_idx = tabline_start_idx

    for i = tabline_start_idx, #all_segments do
        local seg = all_segments[i]
        local needed_width = seg.width
        if #visible_segments > 0 then
            needed_width = needed_width + separator_width
        end

        local remaining_buffers = #all_segments - i
        local need_trailing_symbol = remaining_buffers > 0
        local width_with_trailing = current_width + needed_width
        if need_trailing_symbol then
            width_with_trailing = width_with_trailing
                + right_symbol_with_spacing
        end

        if width_with_trailing <= available_width then
            table.insert(visible_segments, seg)
            current_width = current_width + needed_width
            end_idx = i
        else
            break
        end
    end

    local has_next = end_idx < #all_segments

    local parts = {}

    if has_prev then
        table.insert(
            parts,
            "%#"
                .. window_bg_hl
                .. "# "
                .. "%#"
                .. tabline_page_indicator_hl
                .. "#"
                .. left_symbol
                .. "%#"
                .. window_bg_hl
                .. "#  "
        )
    end

    local segment_strings = {}
    for _, seg in ipairs(visible_segments) do
        table.insert(segment_strings, seg.segment)
    end
    local separator = "%#"
        .. window_bg_hl
        .. "# "
        .. "%#"
        .. tabline_separator_hl
        .. "#"
        .. separator_symbol
        .. "%#"
        .. window_bg_hl
        .. "# "
    table.insert(parts, table.concat(segment_strings, separator))

    if has_next then
        table.insert(
            parts,
            "%#"
                .. window_bg_hl
                .. "#  %="
                .. "%#"
                .. tabline_page_indicator_hl
                .. "#"
                .. right_symbol
                .. "%#"
                .. window_bg_hl
                .. "# "
        )
    else
        table.insert(parts, "%#" .. window_bg_hl .. "#%=")
    end

    return table.concat(parts, ""), end_idx
end

--- Render tabline in expanded state (labels visible, keymaps active)
--- @return nil
local function render_tabline_expanded()
    config = bento.get_config()
    update_marks()

    if #marks == 0 then
        return
    end

    local tabline_str, end_idx = generate_tabline_string(false)
    tabline_end_idx = end_idx
    vim.o.tabline = tabline_str
    vim.o.showtabline = 2

    local smart_labels = smart_labels_cache
    set_selection_keybindings(smart_labels)
end

--- Render tabline in minimal state
--- @return nil
local function render_tabline_minimal()
    config = bento.get_config()
    update_marks()

    if #marks == 0 then
        return
    end

    local tabline_str, end_idx = generate_tabline_string(true)
    tabline_end_idx = end_idx
    vim.o.tabline = tabline_str
    vim.o.showtabline = 2

    clear_selection_keymaps()
end

--- Save original tabline settings
--- @return nil
local function save_tabline_settings()
    if saved_tabline == nil then
        saved_tabline = vim.o.tabline
        saved_showtabline = vim.o.showtabline
    end
end

--- Restore original tabline settings
--- @return nil
local function restore_tabline_settings()
    if saved_tabline ~= nil then
        vim.o.tabline = saved_tabline
        vim.o.showtabline = saved_showtabline
        saved_tabline = nil
        saved_showtabline = nil
    end
end

--- Render the appropriate collapsed view based on minimal_menu mode
--- @return nil
local function render_collapsed()
    if minimal_menu_active == "dashed" then
        render_dashed()
    elseif minimal_menu_active == "filename" then
        render_filename_collapsed()
    elseif minimal_menu_active == "full" then
        render_expanded(true)
    end
end

--- Close the menu completely
--- @return nil
function M.close_menu()
    if is_tabline_ui() then
        restore_tabline_settings()
        tabline_active = false
        is_expanded = false
        tabline_start_idx = 1
        current_action = nil
        clear_selection_keymaps()
        return
    end

    -- Floating UI
    if bento_win_id and vim.api.nvim_win_is_valid(bento_win_id) then
        vim.api.nvim_win_close(bento_win_id, true)
    end
    bento_win_id = nil
    bento_bufh = nil
    is_expanded = false
    current_action = nil
    current_page = 1
    clear_selection_keymaps()
end

--- Go to next page
--- @return nil
function M.next_page()
    if is_tabline_ui() then
        if not tabline_active or not is_expanded then
            return
        end
        if tabline_end_idx < #marks then
            tabline_start_idx = tabline_end_idx + 1
            render_tabline_expanded()
        end
        return
    end

    -- Floating UI
    local _, total_pages, needs_pagination = get_pagination_info()
    if not needs_pagination then
        return
    end
    if current_page < total_pages then
        current_page = current_page + 1
        if is_expanded then
            render_expanded()
        else
            render_collapsed()
        end
    end
end

--- Go to previous page
--- @return nil
function M.prev_page()
    if is_tabline_ui() then
        if not tabline_active or not is_expanded then
            return
        end
        if tabline_start_idx > 1 then
            tabline_start_idx = get_tabline_prev_page_start(tabline_start_idx)
            render_tabline_expanded()
        end
        return
    end

    -- Floating UI
    local _, _, needs_pagination = get_pagination_info()
    if not needs_pagination then
        return
    end
    if current_page > 1 then
        current_page = current_page - 1
        if is_expanded then
            render_expanded()
        else
            render_collapsed()
        end
    end
end

--- Toggle menu (create or close)
--- @param force_create boolean|nil If true, force create menu even without minimal mode
--- @return nil
function M.toggle_menu(force_create)
    M.setup_state()

    if is_tabline_ui() then
        if tabline_active then
            M.close_menu()
            return
        end

        local cur_win = vim.api.nvim_get_current_win()
        local cfg = vim.api.nvim_win_get_config(cur_win)
        if cfg.relative == "" then
            last_editor_win = cur_win
        else
            for _, w in ipairs(vim.api.nvim_list_wins()) do
                local c = vim.api.nvim_win_get_config(w)
                if c.relative == "" then
                    last_editor_win = w
                    break
                end
            end
        end

        update_marks()
        if #marks == 0 then
            vim.notify(
                "No buffers to display",
                vim.log.levels.INFO,
                { title = "Buffer Manager" }
            )
            return
        end

        save_tabline_settings()
        tabline_active = true
        is_expanded = false
        tabline_start_idx = 1
        render_tabline_minimal()
        return
    end

    -- Floating UI
    if bento_win_id and vim.api.nvim_win_is_valid(bento_win_id) then
        M.close_menu()
        return
    end

    local cur_win = vim.api.nvim_get_current_win()
    local cfg = vim.api.nvim_win_get_config(cur_win)
    if cfg.relative == "" then
        last_editor_win = cur_win
    else
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            local c = vim.api.nvim_win_get_config(w)
            if c.relative == "" then
                last_editor_win = w
                break
            end
        end
    end

    update_marks()
    local total_buffers = #marks

    if total_buffers == 0 then
        vim.notify(
            "No buffers to display",
            vim.log.levels.INFO,
            { title = "Buffer Manager" }
        )
        return
    end

    if not minimal_menu_active and not force_create then
        return
    end

    local padding = config.ui.floating.label_padding or 1
    local initial_width = 2 + 2 * padding
    local win_info = create_window(total_buffers, initial_width)
    bento_win_id = win_info.win_id
    bento_bufh = win_info.bufnr

    is_expanded = false
    current_page = 1
    if minimal_menu_active then
        render_collapsed()
    end
end

--- Expand menu to show labels and names
--- @return nil
function M.expand_menu()
    -- Warn if no actions are registered
    if vim.tbl_isempty(config.actions) then
        warn_once(
            "no_actions_registered",
            "No actions registered. Call api.register_action() to register actions."
        )
    end

    -- Warn if no collapse key is registered
    if not registered_collapse_key then
        warn_once(
            "no_collapse_key",
            "No collapse key registered. Call api.register_collapse_key() or use CursorMoved to collapse."
        )
    end

    if is_tabline_ui() then
        if not tabline_active then
            return
        end
        is_expanded = true
        current_action = config.default_action
        render_tabline_expanded()
        return
    end

    -- Floating UI
    if not bento_win_id or not vim.api.nvim_win_is_valid(bento_win_id) then
        return
    end

    is_expanded = true
    current_action = config.default_action
    render_expanded()
end

--- Collapse menu back to minimal view
--- @return nil
function M.collapse_menu()
    M.setup_state()

    if is_tabline_ui() then
        if not tabline_active then
            return
        end
        is_expanded = false
        current_action = nil
        tabline_start_idx = 1
        render_tabline_minimal()
        return
    end

    -- Floating UI
    if not bento_win_id or not vim.api.nvim_win_is_valid(bento_win_id) then
        return
    end

    if not minimal_menu_active then
        M.close_menu()
        return
    end

    is_expanded = false
    current_action = nil
    current_page = 1
    render_collapsed()
end

--- Select buffer by index
--- @param idx number Buffer index in marks list (1-indexed)
--- @return nil
function M.select_buffer(idx)
    local mark = marks[idx]
    if not mark then
        return
    end

    local action_to_use = current_action or config.default_action
    if not action_to_use then
        warn_once(
            "no_default_action",
            "No default action set. Call api.set_default_action() after registering actions."
        )
        return
    end

    local action_config = config.actions[action_to_use]

    if not action_config or not action_config.action then
        warn_once(
            "action_not_registered_" .. action_to_use,
            "Action '"
                .. action_to_use
                .. "' is not registered. Call api.register_action() to register it."
        )
        return
    end

    if action_to_use == "open" then
        bento.record_access(mark.buf_id)

        local target_win = vim.api.nvim_get_current_win()

        if vim.api.nvim_win_get_config(target_win).relative ~= "" then
            target_win = last_editor_win
                    and vim.api.nvim_win_is_valid(last_editor_win)
                    and last_editor_win
                or find_main_window()
        end

        vim.api.nvim_set_current_win(target_win)
    end

    local success, err = pcall(action_config.action, mark.buf_id, mark.filename)
    if not success then
        vim.notify(
            "Action failed: " .. tostring(err),
            vim.log.levels.ERROR,
            { title = "Buffer Manager" }
        )
    else
        current_page = 1
        tabline_start_idx = 1
    end
end

--- Set action mode
--- @param action_name string Name of the action (e.g., "open", "delete", "vsplit")
--- @return nil
function M.set_action_mode(action_name)
    if not config.actions[action_name] then
        vim.notify(
            "Unknown action: " .. action_name,
            vim.log.levels.ERROR,
            { title = "Buffer Manager" }
        )
        return
    end

    current_action = action_name
    vim.notify(
        "Action mode: " .. action_name,
        vim.log.levels.INFO,
        { title = "Buffer Manager" }
    )

    if is_tabline_ui() then
        render_tabline_expanded()
    else
        render_expanded()
    end
end

--- Refresh menu if open
--- @return nil
function M.refresh_menu()
    M.setup_state()

    if is_tabline_ui() then
        if not tabline_active then
            return
        end

        update_marks()

        if #marks == 0 then
            M.close_menu()
            return
        end

        if is_expanded then
            render_tabline_expanded()
        else
            render_tabline_minimal()
        end
        return
    end

    -- Floating UI
    if not bento_win_id or not vim.api.nvim_win_is_valid(bento_win_id) then
        return
    end

    update_marks()

    if #marks == 0 then
        M.close_menu()
        return
    end

    if is_expanded then
        render_expanded()
    else
        if minimal_menu_active then
            render_collapsed()
        end
    end
end

--- Toggle the minimal menu mode dynamically
--- Cycles through: nil -> "dashed" -> "filename" -> "full"
--- Note: This function is ignored when ui.mode = "tabline"
--- @return nil
function M.toggle_minimal_menu()
    M.setup_state()

    if is_tabline_ui() then
        vim.notify(
            "Minimal menu toggle is not available for tabline UI",
            vim.log.levels.INFO,
            { title = "Buffer Manager" }
        )
        return
    end

    local modes = { nil, "dashed", "filename", "full" }
    local current_idx = 1
    for i, mode in ipairs(modes) do
        if minimal_menu_active == mode then
            current_idx = i
            break
        end
    end

    local next_idx = (current_idx % #modes) + 1
    minimal_menu_active = modes[next_idx]

    local mode_name = minimal_menu_active or "disabled"
    vim.notify(
        "Minimal menu: " .. mode_name,
        vim.log.levels.INFO,
        { title = "Buffer Manager" }
    )

    if minimal_menu_active then
        if not bento_win_id or not vim.api.nvim_win_is_valid(bento_win_id) then
            M.toggle_menu()
        else
            if not is_expanded then
                render_collapsed()
            end
        end
    else
        if
            bento_win_id
            and vim.api.nvim_win_is_valid(bento_win_id)
            and not is_expanded
        then
            M.close_menu()
        end
    end
end

--- Open and expand the menu (convenience function)
--- @return nil
function M.open_menu()
    M.setup_state()
    M.toggle_menu(true)
    M.expand_menu()
end

--- Set the registered expand menu key (internal setter, use bento.api for registration)
--- @param key string The key to set
--- @return nil
function M.set_registered_expand_key(key)
    registered_expand_key = key
end

--- Set the registered last buffer key (internal setter, use bento.api for registration)
--- @param key string The key to set
--- @return nil
function M.set_registered_last_buffer_key(key)
    registered_last_buffer_key = key
end

--- Get the registered expand menu key
--- @return string|nil
function M.get_registered_expand_key()
    return registered_expand_key
end

--- Get the registered last buffer key
--- @return string|nil
function M.get_registered_last_buffer_key()
    return registered_last_buffer_key
end

--- Set the registered collapse menu key (internal setter, use bento.api for registration)
--- @param key string The key to set
--- @return nil
function M.set_registered_collapse_key(key)
    registered_collapse_key = key
end

--- Get the registered collapse menu key
--- @return string|nil
function M.get_registered_collapse_key()
    return registered_collapse_key
end

--- Set the registered next page key (internal setter, use bento.api for registration)
--- @param key string The key to set
--- @return nil
function M.set_registered_next_page_key(key)
    registered_next_page_key = key
end

--- Get the registered next page key
--- @return string|nil
function M.get_registered_next_page_key()
    return registered_next_page_key
end

--- Set the registered prev page key (internal setter, use bento.api for registration)
--- @param key string The key to set
--- @return nil
function M.set_registered_prev_page_key(key)
    registered_prev_page_key = key
end

--- Get the registered prev page key
--- @return string|nil
function M.get_registered_prev_page_key()
    return registered_prev_page_key
end

return M
