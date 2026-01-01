local bento = require("bento")
local utils = require("bento.utils")
local marks = require("bento").marks
local line_keys = require("bento").line_keys

local M = {}

local bento_win_id = nil
local bento_bufh = nil
local last_editor_win = nil
local config = bento.get_config()
local is_expanded = false
local selection_mode_keymaps = {} -- Keys we've overridden
local saved_keymaps = {} -- Original keymaps to restore
local current_action = nil -- Track which action mode is active
local show_minimal_menu_active = nil -- Current state of minimal menu

function M.setup_state()
    if show_minimal_menu_active == nil then
        show_minimal_menu_active = config.show_minimal_menu
    end
end

function M.set_last_editor_win(win_id)
    last_editor_win = win_id
end

vim.api.nvim_set_hl(0, "BentoNormal", { bg = "NONE", fg = "NONE" })

-- Check if buffer is visible in current tab
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

-- Get the last accessed buffer not currently visible
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

-- Get the index of a buffer in the marks list
local function get_buffer_index(buf_id)
    for i, mark in ipairs(marks) do
        if mark.buf_id == buf_id then
            return i
        end
    end
    return nil
end

-- Find main content window (non-floating)
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

-- Update marks (buffer list)
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
end

-- Assign smart labels to buffers
local function assign_smart_labels(buffers, available_keys)
    local label_assignment = {}
    local used_labels = {}
    local last_accessed_buf = get_last_accessed_buffer()

    -- Reserve main keymap for last accessed buffer
    if last_accessed_buf then
        for i, mark in ipairs(buffers) do
            if mark.buf_id == last_accessed_buf then
                label_assignment[i] = config.main_keymap
                used_labels[config.main_keymap] = true
                break
            end
        end
    end

    -- Build a mapping of first characters to buffer indices
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

-- Calculate window position based on config.position
-- Supports: "top-left", "top-right", "middle-left", "middle-right",
-- "bottom-left", "bottom-right"
local function calculate_position(height, width)
    local ui = vim.api.nvim_list_uis()[1]
    local position = config.position or "middle-right"
    local offset_x = config.offset_x or 0
    local offset_y = config.offset_y or 0

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

-- Create the transparent floating window
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
        border = "none",
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

-- Update window size dynamically
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

-- Check if buffer is active (i.e., visible in any window)
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

-- Check if buffer is the current buffer in the last editor window
local function is_current_buffer(buf_id)
    return last_editor_win
        and vim.api.nvim_win_is_valid(last_editor_win)
        and vim.api.nvim_win_get_buf(last_editor_win) == buf_id
end

-- Generate dash line for a buffer
local function generate_dash_line(buf_id)
    return is_current_buffer(buf_id) and (config.dash_char:rep(2))
        or (" " .. config.dash_char)
end

-- Save original keymap before overriding
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

-- Restore original keymap
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

-- Clear all selection mode keymaps and restore originals
local function clear_selection_keymaps()
    for _, key in ipairs(selection_mode_keymaps) do
        restore_keymap("n", key)
    end
    selection_mode_keymaps = {}
end

-- Set global keybindings for selection mode
local function set_selection_keybindings(smart_labels)
    clear_selection_keymaps()

    for i, label in pairs(smart_labels) do
        if label and label ~= " " and label ~= config.main_keymap then
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

    vim.keymap.set("n", "<ESC>", function()
        require("bento.ui").collapse_menu()
    end, { silent = true, desc = "Bento: Collapse menu" })
    table.insert(selection_mode_keymaps, "<ESC>")
end

-- Display menu in collapsed state (dashes only)
local function render_collapsed()
    if not bento_bufh or not vim.api.nvim_buf_is_valid(bento_bufh) then
        return
    end

    config = bento.get_config()
    update_marks()
    local contents = {}
    local padding = config.label_padding or 1
    local padding_str = string.rep(" ", padding)

    for i = 1, #marks do
        contents[i] = padding_str
            .. generate_dash_line(marks[i].buf_id)
            .. padding_str
    end

    vim.api.nvim_buf_set_option(bento_bufh, "modifiable", true)
    vim.api.nvim_buf_set_lines(bento_bufh, 0, -1, false, contents)
    vim.api.nvim_buf_set_option(bento_bufh, "modifiable", false)

    local dash_width =
        vim.fn.strwidth(generate_dash_line(marks[1] and marks[1].buf_id or 0))
    update_window_size(dash_width + 2 * padding, #marks)

    local ns_id = vim.api.nvim_create_namespace("BentoDash")
    vim.api.nvim_buf_clear_namespace(bento_bufh, ns_id, 0, -1)

    for i, mark in ipairs(marks) do
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

-- Display menu in expanded state (labels + names)
local function render_expanded()
    if not bento_bufh or not vim.api.nvim_buf_is_valid(bento_bufh) then
        return
    end

    config = bento.get_config()
    update_marks()
    local smart_labels = assign_smart_labels(marks, line_keys)
    local contents = {}
    local padding = config.label_padding or 1
    local padding_str = string.rep(" ", padding)

    local all_paths = {}
    for _, mark in ipairs(marks) do
        table.insert(all_paths, mark.filename)
    end
    local display_names = utils.get_display_names(all_paths)

    local max_content_width = 0
    local line_data = {}

    for i, mark in ipairs(marks) do
        local label = smart_labels[i] or " "
        local display_name = display_names[mark.filename]
            or utils.get_file_name(mark.filename)
        -- Format: [display_name] [space] [padding][label][padding]
        local content_width = vim.fn.strwidth(display_name)
            + 1
            + padding
            + #label
            + padding
        max_content_width = math.max(max_content_width, content_width)
        table.insert(line_data, {
            label = label,
            display_name = display_name,
            content_width = content_width,
        })
    end

    local total_width = padding + max_content_width

    for i, data in ipairs(line_data) do
        local left_space = max_content_width - data.content_width
        -- Format: [padding][left_space][display_name] [space] [padding][label][padding]
        local line = padding_str
            .. string.rep(" ", left_space)
            .. data.display_name
            .. " "
            .. padding_str
            .. data.label
            .. padding_str
        contents[i] = line
    end

    vim.api.nvim_buf_set_option(bento_bufh, "modifiable", true)
    vim.api.nvim_buf_set_lines(bento_bufh, 0, -1, false, contents)
    vim.api.nvim_buf_set_option(bento_bufh, "modifiable", false)

    update_window_size(total_width, #marks)

    local ns_id = vim.api.nvim_create_namespace("BentoLabel")
    vim.api.nvim_buf_clear_namespace(bento_bufh, ns_id, 0, -1)

    for i, mark in ipairs(marks) do
        local label = smart_labels[i]
        local is_current = is_current_buffer(mark.buf_id)
        local is_active = is_buffer_active(mark.buf_id)
        local is_modified = vim.api.nvim_buf_get_option(mark.buf_id, "modified")
        local data = line_data[i]

        if label and label ~= " " then
            local left_space = max_content_width - data.content_width
            local display_name_start = padding + left_space
            local display_name_end = display_name_start
                + vim.fn.strwidth(data.display_name)
            local label_start = display_name_end + 1 + padding
            local label_end = label_start + #label + padding

            local label_hl
            local is_previous_buffer = config.main_keymap
                and label == config.main_keymap
            if is_previous_buffer then
                label_hl = config.highlights.previous
            else
                local action_name = current_action
                    or config.default_action
                    or "open"
                label_hl = config.highlights.label_open

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

    set_selection_keybindings(smart_labels)
end

-- Close the menu completely
function M.close_menu()
    if bento_win_id and vim.api.nvim_win_is_valid(bento_win_id) then
        vim.api.nvim_win_close(bento_win_id, true)
    end
    bento_win_id = nil
    bento_bufh = nil
    is_expanded = false
    current_action = nil
    clear_selection_keymaps()
end

-- Toggle menu (create or close)
function M.toggle_menu(force_create)
    M.setup_state()

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

    if not show_minimal_menu_active and not force_create then
        return
    end

    local padding = config.label_padding or 1
    local initial_width = 2 + 2 * padding
    local win_info = create_window(total_buffers, initial_width)
    bento_win_id = win_info.win_id
    bento_bufh = win_info.bufnr

    is_expanded = false
    if show_minimal_menu_active then
        render_collapsed()
    end
end

-- Expand menu to show labels and names
function M.expand_menu()
    if not bento_win_id or not vim.api.nvim_win_is_valid(bento_win_id) then
        return
    end

    is_expanded = true
    current_action = config.default_action or "open"
    render_expanded()
end

-- Collapse menu back to dashes
function M.collapse_menu()
    M.setup_state()
    if not bento_win_id or not vim.api.nvim_win_is_valid(bento_win_id) then
        return
    end

    if not show_minimal_menu_active then
        M.close_menu()
        return
    end

    is_expanded = false
    current_action = nil
    render_collapsed()
end

-- Select buffer by index
function M.select_buffer(idx)
    local mark = marks[idx]
    if not mark then
        return
    end

    local action_to_use = current_action or "open"
    local action_config = config.actions[action_to_use]

    if not action_config or not action_config.action then
        vim.notify(
            "Invalid action: " .. action_to_use,
            vim.log.levels.ERROR,
            { title = "Buffer Manager" }
        )
        return
    end

    if action_to_use == "open" then
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
    end
end

-- Set action mode
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

    render_expanded()
end

-- Handle main keymap press
function M.handle_main_keymap()
    M.setup_state()
    if bento_win_id and vim.api.nvim_win_is_valid(bento_win_id) then
        if is_expanded then
            local last_buf = get_last_accessed_buffer()
            if last_buf then
                local buf_idx = get_buffer_index(last_buf)
                if buf_idx then
                    M.select_buffer(buf_idx)
                end
            end
        else
            M.expand_menu()
        end
    elseif not show_minimal_menu_active then
        M.toggle_menu(true)
        M.expand_menu()
    else
        M.toggle_menu()
    end
end

-- Refresh menu if open
function M.refresh_menu()
    M.setup_state()
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
        if show_minimal_menu_active then
            render_collapsed()
        end
    end
end

-- Toggle the minimal menu preference dynamically
function M.toggle_minimal_menu()
    M.setup_state()
    show_minimal_menu_active = not show_minimal_menu_active

    if show_minimal_menu_active then
        vim.notify(
            "Minimal menu enabled",
            vim.log.levels.INFO,
            { title = "Buffer Manager" }
        )
    else
        vim.notify(
            "Minimal menu disabled",
            vim.log.levels.INFO,
            { title = "Buffer Manager" }
        )
        if
            bento_win_id
            and vim.api.nvim_win_is_valid(bento_win_id)
            and not is_expanded
        then
            M.close_menu()
        end
    end
end

return M
