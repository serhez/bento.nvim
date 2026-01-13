--- Bento.nvim - A buffer management plugin for Neovim
--- @module bento

local utils = require("bento.utils")

local M = {}

--- Global configuration table for bento.nvim
BentoConfig = BentoConfig or {}

--- List of buffer marks (tracked buffers with filename and buf_id)
--- @type table[]
M.marks = {}

--- Metrics for each buffer (access times, edit times)
--- @type table<number, {access_times: number[], edit_times: number[]}>
M.buffer_metrics = {}

--- Set of locked buffer IDs (protected from automatic deletion)
--- @type table<number, boolean>
M.locked_buffers = {}

--- Get current time in milliseconds
--- @return number
local function get_time_ms()
    return vim.uv.hrtime() / 1e6
end

--- Get the current plugin configuration
--- @return table
function M.get_config()
    return BentoConfig or {}
end

--- Save locked buffer paths to a global variable for session storage
--- @return nil
local function save_locked_buffers()
    local locked_paths = {}
    for buf_id, _ in pairs(M.locked_buffers) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            local path = vim.api.nvim_buf_get_name(buf_id)
            if path and path ~= "" then
                table.insert(locked_paths, path)
            end
        end
    end
    vim.g.BentoLockedBuffers = vim.json.encode(locked_paths)
end

--- Decode locked paths from global variable
--- @return string[]|nil
local function get_locked_paths()
    local raw = vim.g.BentoLockedBuffers
    if not raw then
        return nil
    end
    if type(raw) == "string" then
        local ok, decoded = pcall(vim.json.decode, raw)
        if ok and type(decoded) == "table" then
            return decoded
        end
        return nil
    elseif type(raw) == "table" then
        return raw
    end
    return nil
end

--- Restore locked buffers from global variable
--- @return nil
local function restore_locked_buffers()
    local locked_paths = get_locked_paths()
    if not locked_paths then
        return
    end

    for _, path in ipairs(locked_paths) do
        local buf_id = vim.fn.bufnr(path)
        if buf_id ~= -1 and vim.api.nvim_buf_is_valid(buf_id) then
            M.locked_buffers[buf_id] = true
        end
    end
end

--- Save buffer metrics to a global variable for session storage
--- Only saves last access/edit time per path to keep data compact
--- @return nil
local function save_buffer_metrics()
    local metrics_by_path = {}
    for buf_id, metrics in pairs(M.buffer_metrics) do
        if vim.api.nvim_buf_is_valid(buf_id) then
            local path = vim.api.nvim_buf_get_name(buf_id)
            if path and path ~= "" then
                local last_access = metrics.access_times[#metrics.access_times]
                local last_edit = metrics.edit_times[#metrics.edit_times]
                if last_access or last_edit then
                    metrics_by_path[path] = {
                        a = last_access,
                        e = last_edit,
                    }
                end
            end
        end
    end
    vim.g.BentoBufferMetrics = vim.json.encode(metrics_by_path)
end

--- Decode buffer metrics from global variable
--- @return table<string, {a: number?, e: number?}>|nil
local function get_saved_buffer_metrics()
    local raw = vim.g.BentoBufferMetrics
    if not raw then
        return nil
    end
    if type(raw) == "string" then
        local ok, decoded = pcall(vim.json.decode, raw)
        if ok and type(decoded) == "table" then
            return decoded
        end
        return nil
    elseif type(raw) == "table" then
        return raw
    end
    return nil
end

--- Restore buffer metrics from global variable
--- @return nil
local function restore_buffer_metrics()
    local saved_metrics = get_saved_buffer_metrics()
    if not saved_metrics then
        return
    end

    for path, metrics in pairs(saved_metrics) do
        local buf_id = vim.fn.bufnr(path)
        if buf_id ~= -1 and vim.api.nvim_buf_is_valid(buf_id) then
            M.buffer_metrics[buf_id] = {
                access_times = metrics.a and { metrics.a } or {},
                edit_times = metrics.e and { metrics.e } or {},
            }
        end
    end
end

--- Built-in actions for buffer operations
--- @type table<string, {key: string, hl: string, action: function}>
M.actions = {
    open = {
        key = "<CR>",
        hl = "DiagnosticVirtualTextHint",
        action = function(_, buf_name)
            local bufnr = vim.fn.bufnr(buf_name)
            if bufnr ~= -1 then
                vim.cmd("buffer " .. bufnr)
            else
                vim.cmd("edit " .. buf_name)
            end
            require("bento.ui").collapse_menu()
        end,
    },
    delete = {
        key = "<BS>",
        hl = "DiagnosticVirtualTextError",
        action = function(buf_id, _)
            vim.api.nvim_buf_delete(buf_id, { force = false })
            require("bento.ui").refresh_menu()
        end,
    },
    vsplit = {
        key = "|",
        hl = "DiagnosticVirtualTextInfo",
        action = function(_, buf_name)
            local bufnr = vim.fn.bufnr(buf_name)
            if bufnr ~= -1 then
                vim.cmd("vsplit | buffer " .. bufnr)
            else
                vim.cmd("vsplit " .. buf_name)
            end
            require("bento.ui").collapse_menu()
        end,
    },
    split = {
        key = "_",
        hl = "DiagnosticVirtualTextInfo",
        action = function(_, buf_name)
            local bufnr = vim.fn.bufnr(buf_name)
            if bufnr ~= -1 then
                vim.cmd("split | buffer " .. bufnr)
            else
                vim.cmd("split " .. buf_name)
            end
            require("bento.ui").collapse_menu()
        end,
    },
    lock = {
        key = "*",
        hl = "DiagnosticVirtualTextWarn",
        action = function(buf_id, _)
            require("bento").toggle_lock(buf_id)
            require("bento.ui").refresh_menu()
        end,
    },
}

--- Keys available for buffer labels (a-z, A-Z, 0-9)
--- @type string[]
M.line_keys = {
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z",
    "A",
    "B",
    "C",
    "D",
    "E",
    "F",
    "G",
    "H",
    "I",
    "J",
    "K",
    "L",
    "M",
    "N",
    "O",
    "P",
    "Q",
    "R",
    "S",
    "T",
    "U",
    "V",
    "W",
    "X",
    "Y",
    "Z",
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
}

--- Set up the main keymap for toggling the buffer menu
--- @return nil
local function setup_main_keymap()
    local config = M.get_config()
    if config.main_keymap and config.main_keymap ~= "" then
        vim.keymap.set(
            "n",
            config.main_keymap,
            "<Cmd>lua require('bento.ui').handle_main_keymap()<CR>",
            { silent = true, desc = "Buffer Manager" }
        )
    end
end

--- Set up autocommands for buffer tracking and menu updates
--- @return nil
local function setup_autocmds()
    vim.api.nvim_create_user_command("BentoToggle", function()
        require("bento.ui").toggle_menu()
    end, { desc = "Toggle bento menu" })

    vim.api.nvim_create_user_command("BentoToggleMinimalMenu", function()
        require("bento.ui").toggle_minimal_menu()
    end, { desc = "Toggle bento minimal menu rendering" })

    local function is_menu_buffer(bufnr)
        local ok, val = pcall(vim.api.nvim_buf_get_var, bufnr, "bento_menu")
        return ok and val
    end

    local augroup =
        vim.api.nvim_create_augroup("BentoRefresh", { clear = true })

    vim.api.nvim_create_autocmd(
        { "BufAdd", "BufDelete", "BufWipeout", "BufEnter", "WinEnter" },
        {
            group = augroup,
            callback = function(args)
                if is_menu_buffer(args.buf) then
                    return
                end
                if
                    vim.bo[args.buf].buftype ~= ""
                    and vim.bo[args.buf].buftype ~= "terminal"
                then
                    return
                end
                require("bento.ui").refresh_menu()
            end,
            desc = "Auto-refresh bento menu",
        }
    )

    vim.api.nvim_create_autocmd("WinEnter", {
        group = augroup,
        callback = function(args)
            if is_menu_buffer(args.buf) then
                return
            end
            local win_id = vim.api.nvim_get_current_win()
            if not win_id or win_id == nil then
                return
            end
            require("bento.ui").set_last_editor_win(win_id)
        end,
        desc = "Update current window in bento menu",
    })

    vim.api.nvim_create_autocmd("CursorMoved", {
        group = augroup,
        callback = function(args)
            if is_menu_buffer(args.buf) then
                return
            end
            require("bento.ui").collapse_menu()
        end,
        desc = "Collapse bento menu on cursor move",
    })

    vim.api.nvim_create_autocmd("VimResized", {
        group = augroup,
        callback = function()
            require("bento.ui").refresh_menu()
        end,
        desc = "Refresh bento menu on window resize",
    })

    vim.api.nvim_create_autocmd("BufAdd", {
        group = augroup,
        callback = function(args)
            if is_menu_buffer(args.buf) then
                return
            end
            require("bento").enforce_buffer_limit()
        end,
        desc = "Enforce maximum buffer limit",
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        group = augroup,
        callback = function(args)
            if is_menu_buffer(args.buf) then
                return
            end
            if vim.bo[args.buf].buftype ~= "" then
                return
            end
            require("bento").record_access(args.buf)
        end,
        desc = "Track buffer access for deletion metrics",
    })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = augroup,
        callback = function(args)
            if is_menu_buffer(args.buf) then
                return
            end
            if vim.bo[args.buf].buftype ~= "" then
                return
            end
            require("bento").record_edit(args.buf)
        end,
        desc = "Track buffer edits for deletion metrics",
    })

    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = augroup,
        callback = function(args)
            require("bento").cleanup_metrics(args.buf)
        end,
        desc = "Clean up buffer metrics on deletion",
    })

    vim.api.nvim_create_autocmd("BufAdd", {
        group = augroup,
        callback = function(args)
            local locked_paths = get_locked_paths()
            if not locked_paths then
                return
            end
            local buf_path = vim.api.nvim_buf_get_name(args.buf)
            if buf_path and buf_path ~= "" then
                for _, path in ipairs(locked_paths) do
                    if path == buf_path then
                        require("bento").locked_buffers[args.buf] = true
                        break
                    end
                end
            end
        end,
        desc = "Restore locked buffer state from session",
    })

    vim.api.nvim_create_autocmd("BufAdd", {
        group = augroup,
        callback = function(args)
            local saved_metrics = get_saved_buffer_metrics()
            if not saved_metrics then
                return
            end
            local buf_path = vim.api.nvim_buf_get_name(args.buf)
            if buf_path and buf_path ~= "" and saved_metrics[buf_path] then
                local metrics = saved_metrics[buf_path]
                require("bento").buffer_metrics[args.buf] = {
                    access_times = metrics.a and { metrics.a } or {},
                    edit_times = metrics.e and { metrics.e } or {},
                }
            end
        end,
        desc = "Restore buffer metrics from session",
    })

    vim.api.nvim_create_autocmd("SessionLoadPost", {
        group = augroup,
        callback = function()
            restore_locked_buffers()
            restore_buffer_metrics()
        end,
        desc = "Restore locked buffers and buffer metrics after session load",
    })
end

--- Initialize or get metrics for a buffer
--- @param buf_id number Buffer ID
--- @return {access_times: number[], edit_times: number[]}
local function get_buffer_metrics(buf_id)
    if not M.buffer_metrics[buf_id] then
        M.buffer_metrics[buf_id] = {
            access_times = {},
            edit_times = {},
        }
    end
    return M.buffer_metrics[buf_id]
end

--- Record a buffer access event
--- @param buf_id number Buffer ID
--- @return nil
function M.record_access(buf_id)
    local metrics = get_buffer_metrics(buf_id)
    table.insert(metrics.access_times, get_time_ms())
    save_buffer_metrics()
end

--- Record a buffer edit event
--- @param buf_id number Buffer ID
--- @return nil
function M.record_edit(buf_id)
    local metrics = get_buffer_metrics(buf_id)
    table.insert(metrics.edit_times, get_time_ms())
    save_buffer_metrics()
end

--- Clean up metrics for deleted buffers
--- @param buf_id number Buffer ID
--- @return nil
function M.cleanup_metrics(buf_id)
    M.buffer_metrics[buf_id] = nil
    save_buffer_metrics()
    if M.locked_buffers[buf_id] then
        M.locked_buffers[buf_id] = nil
        save_locked_buffers()
    end
end

--- Check if a buffer is locked
--- @param buf_id number|nil Buffer ID (defaults to current buffer)
--- @return boolean
function M.is_locked(buf_id)
    buf_id = buf_id or vim.api.nvim_get_current_buf()
    return M.locked_buffers[buf_id] == true
end

--- Toggle the lock status of a buffer
--- Locked buffers are protected from automatic deletion
--- @param buf_id number|nil Buffer ID (defaults to current buffer)
--- @return boolean Whether the buffer is now locked
function M.toggle_lock(buf_id)
    buf_id = buf_id or vim.api.nvim_get_current_buf()
    if M.locked_buffers[buf_id] then
        M.locked_buffers[buf_id] = nil
    else
        M.locked_buffers[buf_id] = true
    end
    save_locked_buffers()
    return M.locked_buffers[buf_id] == true
end

--- Calculate frecency score for a list of timestamps
--- Uses a decay-based algorithm where recent events score higher
--- Formula: sum of (1 / (1 + age_in_hours)) for each event
--- @param timestamps number[] List of timestamps in milliseconds
--- @return number Frecency score
local function calculate_frecency(timestamps)
    if not timestamps or #timestamps == 0 then
        return 0
    end

    local now = get_time_ms()
    local score = 0

    for _, timestamp in ipairs(timestamps) do
        local age_hours = (now - timestamp) / (1000 * 3600)
        score = score + (1 / (1 + age_hours))
    end

    return score
end

--- Get the metric value for a buffer based on the configured metric type
--- @param buf_id number Buffer ID
--- @param metric_type string One of "recency_access", "recency_edit", "frecency_access", "frecency_edit"
--- @return number Metric value
local function get_buffer_metric_value(buf_id, metric_type)
    local metrics = M.buffer_metrics[buf_id]

    if metric_type == "recency_access" then
        local buf_info = vim.fn.getbufinfo(buf_id)[1]
        if buf_info then
            return buf_info.lastused or 0
        end
        return 0
    elseif metric_type == "recency_edit" then
        if metrics and #metrics.edit_times > 0 then
            return metrics.edit_times[#metrics.edit_times]
        end
        return 0
    elseif metric_type == "frecency_access" then
        if metrics then
            return calculate_frecency(metrics.access_times)
        end
        return 0
    elseif metric_type == "frecency_edit" then
        if metrics then
            return calculate_frecency(metrics.edit_times)
        end
        return 0
    end

    local buf_info = vim.fn.getbufinfo(buf_id)[1]
    if buf_info then
        return buf_info.lastused or 0
    end
    return 0
end

--- Get the ordering metric value for a buffer (used for sorting)
--- Returns higher values for more recently accessed/edited buffers
--- @param buf_id number Buffer ID
--- @return number Ordering value
function M.get_ordering_value(buf_id)
    local config = M.get_config()
    local ordering_metric = config.ordering_metric

    if not ordering_metric then
        return 0
    end

    local metrics = M.buffer_metrics[buf_id]

    if ordering_metric == "access" then
        if metrics and #metrics.access_times > 0 then
            return metrics.access_times[#metrics.access_times]
        end
        local buf_info = vim.fn.getbufinfo(buf_id)[1]
        if buf_info then
            return buf_info.lastused or 0
        end
        return 0
    elseif ordering_metric == "edit" then
        if metrics and #metrics.edit_times > 0 then
            return metrics.edit_times[#metrics.edit_times]
        end
        return 0
    end

    return 0
end

--- Initialize marks for all valid buffers
--- @return nil
function M.initialize_marks()
    for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
        local buf_name = vim.api.nvim_buf_get_name(buf_id)
        if utils.buffer_is_valid(buf_id, buf_name) then
            table.insert(M.marks, { filename = buf_name, buf_id = buf_id })
        end
    end
end

--- Get buffer to delete based on configured metric (excluding current, visible, and locked buffers)
--- @return number|nil Buffer ID of the least recently used buffer, or nil if none found
function M.get_lru_buffer()
    local config = M.get_config()
    local metric_type = config.buffer_deletion_metric or "recency_access"
    local current_buf = vim.api.nvim_get_current_buf()
    local visible_bufs = {}

    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
            local buf = vim.api.nvim_win_get_buf(win)
            visible_bufs[buf] = true
        end
    end

    local candidate_buf = nil
    local candidate_score = math.huge

    for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
        local buf_name = vim.api.nvim_buf_get_name(buf_id)
        if
            utils.buffer_is_valid(buf_id, buf_name)
            and buf_id ~= current_buf
            and not visible_bufs[buf_id]
            and not M.locked_buffers[buf_id]
        then
            local score = get_buffer_metric_value(buf_id, metric_type)
            if score < candidate_score then
                candidate_score = score
                candidate_buf = buf_id
            end
        end
    end

    return candidate_buf
end

--- Enforce buffer limit by deleting LRU buffer if needed
--- @return nil
function M.enforce_buffer_limit()
    local config = M.get_config()
    if not config.max_open_buffers or config.max_open_buffers <= 0 then
        return
    end

    local valid_buffers = 0
    for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
        local buf_name = vim.api.nvim_buf_get_name(buf_id)
        if utils.buffer_is_valid(buf_id, buf_name) then
            valid_buffers = valid_buffers + 1
        end
    end

    while valid_buffers > config.max_open_buffers do
        local lru_buf = M.get_lru_buffer()
        if not lru_buf then
            break
        end

        local buf_name = vim.api.nvim_buf_get_name(lru_buf)
        local display_name = buf_name ~= "" and utils.get_file_name(buf_name)
            or "[No Name]"
        local ok = pcall(vim.api.nvim_buf_delete, lru_buf, { force = false })
        if ok and config.buffer_notify_on_delete then
            vim.notify(
                "Deleted buffer " .. display_name,
                vim.log.levels.INFO,
                { title = "Buffer Manager" }
            )
        end
        valid_buffers = valid_buffers - 1
    end
end

--- Validate config structure
--- @param config table Configuration table to validate
--- @return string|nil Error message or nil if valid
local function validate_config(config)
    if config.ui ~= nil and type(config.ui) ~= "table" then
        return '`ui` must be a table, e.g. `ui = { mode = "floating" }`'
    end
    if config.ui then
        if
            config.ui.floating ~= nil
            and type(config.ui.floating) ~= "table"
        then
            return "`ui.floating` must be a table"
        end
        if config.ui.tabline ~= nil and type(config.ui.tabline) ~= "table" then
            return "`ui.tabline` must be a table"
        end
    end
    return nil
end

--- Initialize the plugin with the given configuration
--- @param config table|nil User configuration table
--- @return nil
function M.setup(config)
    config = config or {}

    local config_err = validate_config(config)
    if config_err then
        vim.notify(
            "bento.nvim: Invalid config - " .. config_err,
            vim.log.levels.ERROR
        )
        return
    end

    local default_config = {
        main_keymap = ";",
        lock_char = "🔒",
        default_action = "open",
        max_open_buffers = nil, -- nil (unlimited) or number
        buffer_deletion_metric = "frecency_access", -- "recency_access", "recency_edit", "frecency_access", "frecency_edit"
        buffer_notify_on_delete = true,
        ordering_metric = "access", -- nil (arbitrary) | "access" | "edit"

        ui = {
            mode = "floating", -- "floating" | "tabline"
            floating = {
                position = "middle-right",
                offset_x = 0,
                offset_y = 0,
                dash_char = "─",
                label_padding = 1,
                minimal_menu = nil, -- nil | "dashed" | "filename" | "full"
                max_rendered_buffers = nil, -- nil (no limit) or number
            },
            tabline = {
                left_page_symbol = "❮",
                right_page_symbol = "❯",
                separator_symbol = "│",
            },
        },

        highlights = {
            current = "Bold",
            active = "Normal",
            inactive = "Comment",
            modified = "DiagnosticWarn",
            inactive_dash = "Comment",
            previous = "Search",
            label_open = "DiagnosticVirtualTextHint",
            label_delete = "DiagnosticVirtualTextError",
            label_vsplit = "DiagnosticVirtualTextInfo",
            label_split = "DiagnosticVirtualTextInfo",
            label_lock = "DiagnosticVirtualTextWarn",
            label_minimal = "Visual",
            window_bg = "BentoNormal",
            page_indicator = "Comment",
            separator = "Comment",
        },
    }

    BentoConfig = utils.merge_tables(default_config, config)

    M.actions.open.hl = BentoConfig.highlights.label_open
    M.actions.delete.hl = BentoConfig.highlights.label_delete
    M.actions.vsplit.hl = BentoConfig.highlights.label_vsplit
    M.actions.split.hl = BentoConfig.highlights.label_split
    M.actions.lock.hl = BentoConfig.highlights.label_lock

    BentoConfig.actions = M.actions

    if config.actions then
        BentoConfig.actions = utils.merge_tables(M.actions, config.actions)
    end

    local reserved = { "<Esc>", BentoConfig.main_keymap, "[", "]" }
    for _, action_config in pairs(BentoConfig.actions) do
        if action_config.key then
            table.insert(reserved, action_config.key)
        end
    end
    M.line_keys = vim.tbl_filter(function(key)
        return not vim.tbl_contains(reserved, key)
    end, M.line_keys)

    setup_main_keymap()

    vim.defer_fn(function()
        require("bento").enforce_buffer_limit()
    end, 50)

    vim.defer_fn(function()
        require("bento.ui").setup_state()
        if BentoConfig.ui.mode == "tabline" then
            require("bento.ui").toggle_menu()
        elseif BentoConfig.ui.floating.minimal_menu then
            require("bento.ui").toggle_menu()
        end
    end, 100)

    setup_autocmds()

    M.initialize_marks()

    restore_locked_buffers()
end

return M
