<div align="center">

![logo](https://github.com/user-attachments/assets/2105a347-4218-4afb-b20b-74fcbcff4b5a)

# 🍱 bento.nvim

A minimalist and efficient yet powerful buffer manager for Neovim. Designed to be extensible and customizable, both in terms of UI & functionality.

</div>

## Showcase

<details>

<summary>Default UI. Built-in actions: selection, deletion, splitting, and locking.</summary>

https://github.com/user-attachments/assets/e0429af6-575e-48ea-bb9b-207526c7df13

</details>

<details>

<summary>Dashed UI when collapsed. Built-in pagination. Non-saved highlights.</summary>

https://github.com/user-attachments/assets/d9a636e2-3cd5-4549-be34-3bfe0b8cdec7

</details>

<details>

<summary>Tabline UI with built-in pagination. Built-in actions. Auto-deletion & notifications.</summary>

https://github.com/user-attachments/assets/69a4afc2-3258-4f43-9ffe-882d502cfafd

</details>

<details>

<summary>Custom menu placement. Non-hidden collapsed UI. Built-in actions.</summary>

https://github.com/user-attachments/assets/2f254dc0-9607-4bd4-84c6-f5b431f02b4f

</details>

## Features

- **Two UI modes**: Floating window (default) or tabline integration
- **Extensible action system** with visual feedback (built-in action functions: open, delete, split, lock - registered via API)
- **Customizable UI** with multiple collapsed states (dashes, filenames, full, or hidden) and placement options
- **Smart one-char label assignment** based on filenames for quick buffer switching
- **Last accessed buffer quick switch** with configurable keymap
- **Buffer limit enforcement** with configurable deletion metrics (optional)
- **Buffer locking** to protect important buffers from automatic deletion (persisted across sessions)
- **Pagination** for large buffer lists (automatic when exceeding screen space, or configurable via `max_rendered_buffers`)
- **Configurable buffer ordering** by access time or edit time (most recent first)

## Installation

Neovim 0.9.0+ required. Install with your preferred plugin manager:

```lua
-- lazy.nvim
{ "serhez/bento.nvim", opts = {} }

-- packer.nvim
use({ "serhez/bento.nvim", config = function() require("bento").setup() end })
```

### Setting Up Keymaps

Bento does not register any keymaps or actions by default—you have full control. For a complete lazy.nvim setup:

```lua
{
    "serhez/bento.nvim",
    config = function()
        require("bento").setup({
            -- your config options here
        })

        local api = require("bento.api")

        -- Register menu keymaps
        api.register_expand_key("<YOUR_EXPAND_KEY>")  -- Open/expand menu
        api.register_last_buffer_key("<YOUR_LB_KEY>") -- Label for last-accessed buffer
        api.register_collapse_key("<Esc>")            -- Collapse/close menu
        api.register_prev_page_key("[")               -- Previous page (pagination)
        api.register_next_page_key("]")               -- Next page (pagination)

        -- Register built-in actions (using built-in action functions)
        -- with example keymaps and highlights
        api.register_action("open", {
            key = "<CR>",
            action = api.actions.open,
            hl = "DiagnosticVirtualTextHint",
        })
        api.register_action("delete", {
            key = "<BS>",
            action = api.actions.delete,
            hl = "DiagnosticVirtualTextError",
        })
        api.register_action("vsplit", {
            key = "|",
            action = api.actions.vsplit,
            hl = "DiagnosticVirtualTextInfo",
        })
        api.register_action("split", {
            key = "_",
            action = api.actions.split,
            hl = "DiagnosticVirtualTextInfo",
        })
        api.register_action("lock", {
            key = "*",
            action = api.actions.lock,
            hl = "DiagnosticVirtualTextWarn",
        })

        -- Set default action
        api.set_default_action("open")
    end,
}
```

**That's it!** With this setup:
- Press `<YOUR_EXPAND_KEY>` to open the expanded menu showing buffer labels and names
- The last-accessed buffer will have `<YOUR_LB_KEY>` as its label (unless `config.map_last_accessed=true`, in which case a filename-based label will be assigned to it, but the `<YOUR_LB_KEY>` keymap can still be used to select it in addition to the assigned label)
- **Pro-tip**: make `<YOUR_EXPAND_KEY>` and `<YOUR_LB_KEY>` to be the same; these functionalities do not conflict with each other, and you can achieve a fast switch-to-last-buffer action this way
- Press `<BS>` then a label to delete that buffer; similarly you can perform other actions with your other registered keymaps
- Press any label key directly to execute the default action on that buffer
- Press `<Esc>` to close/collapse the menu
- Press `[` and `]` to go to the previous and next pages (when pagination is needed)

## Visual States

Bento supports two UI modes: **floating window** (default) and **tabline**. Set via `ui.mode = "floating"` or `ui.mode = "tabline"`.

### Floating Window UI

**Collapsed/Minimal:** Configurable via `ui.floating.minimal_menu` option:
- `nil` (default): No collapsed menu shown
- `"dashed"`: Shows dashes only
  - `──` = Active buffer (visible)
  - ` ─` = Inactive buffer (hidden)
- `"filename"`: Shows filenames only (no labels)
- `"full"`: Shows full menu (filenames + labels) with distinct highlighting

**Expanded:** Shows buffer names + labels (right-aligned)
- **Bold** = Current buffer
- Normal = Active in other windows
- *Dimmed* = Inactive
* Modified = Modified buffers (non-saved) can be assigned a special highlight too

### Tabline UI

When `ui.mode = "tabline"`, bento renders buffers horizontally in the tabline instead of a floating window.

**Minimal state:** Labels are shown with `label_minimal` highlight, keymaps are not active
**Expanded state:** Labels use action-specific highlights, keymaps are active

Each buffer displays: `[label] [lock] filename` with consistent background using `window_bg`.

**Pagination:** When there are more buffers than can fit on screen, pagination indicators appear:
- `❮` on the left edge indicates previous buffers exist
- `❯` on the right edge indicates more buffers ahead
- Use `[` and `]` keys to navigate between pages (only when expanded)
- Each page shows a completely different set of buffers

The `ui.floating.minimal_menu` option is ignored when using tabline UI.

## Actions

**Bento does not register any actions by default.** You must explicitly register each action via the API. This gives you full control over which actions are available and what keys they use.

Built-in action functions are available at `api.actions.*`:
- `api.actions.open` — Opens selected buffer in current window
- `api.actions.delete` — Deletes selected buffer
- `api.actions.vsplit` — Opens selected buffer in a vertical split
- `api.actions.split` — Opens selected buffer in a horizontal split
- `api.actions.lock` — Toggles lock on selected buffer (locked buffers are protected from automatic deletion)

### Registering Actions

Use `api.register_action(name, opts)` to register an action:

```lua
local api = require("bento.api")

-- Register built-in actions with your chosen keys and highlights
api.register_action("open", {
    key = "<CR>",
    action = api.actions.open,
    hl = "DiagnosticVirtualTextHint", -- Optional: label highlight for this action
})
api.register_action("delete", {
    key = "<BS>",
    action = api.actions.delete,
    hl = "DiagnosticVirtualTextError",
})
api.register_action("vsplit", {
    key = "|",
    action = api.actions.vsplit,
    hl = "DiagnosticVirtualTextInfo",
})
api.register_action("split", {
    key = "_",
    action = api.actions.split,
    hl = "DiagnosticVirtualTextInfo",
})
api.register_action("lock", {
    key = "*",
    action = api.actions.lock,
    hl = "DiagnosticVirtualTextWarn",
})

-- Set the default action (executed when pressing a label key directly)
api.set_default_action("open")
```

### Custom Actions

You can register custom actions with your own functions:

```lua
api.register_action("git_stage", {
    key = "g",
    hl = "DiffAdd", -- Optional: custom label highlight
    action = function(buf_id, buf_name)
        vim.cmd("!git add " .. vim.fn.shellescape(buf_name))
    end,
})
```

Action fields: `key` (required), `action` (required), `hl` (optional highlight group)

## Configuration

All options with defaults:

```lua
require("bento").setup({
    lock_char = "🔒", -- Character shown before locked buffer names
    max_open_buffers = nil, -- Max buffers (nil = unlimited)
    buffer_deletion_metric = "frecency_access", -- Metric for buffer deletion (see below)
    buffer_notify_on_delete = true, -- Notify when deleting a buffer (false for silent deletion)
    ordering_metric = "access", -- Buffer ordering: nil (arbitrary), "access", or "edit"

    -- If true, last-accessed buffer gets a normal label instead of the registered keymap,
    -- but the last-accessed keymap can still be used to select it in addition to the assigned label
    map_last_accessed = false,

    ui = {
        mode = "floating", -- "floating" | "tabline"
        floating = {
            position = "middle-right", -- See position options below
            offset_x = 0, -- Horizontal offset from position
            offset_y = 0, -- Vertical offset from position
            dash_char = "─", -- Character for collapsed dashes
            border = "none", -- "rounded" | "single" | "double" | etc. (see :h winborder)
            label_padding = 1, -- Padding around labels
            minimal_menu = nil, -- nil | "dashed" | "filename" | "full"
            max_rendered_buffers = nil, -- nil (no limit) or number for pagination
        },
        tabline = {
            left_page_symbol = "❮", -- Symbol shown when previous buffers exist
            right_page_symbol = "❯", -- Symbol shown when more buffers exist
            separator_symbol = "│", -- Separator between buffer components
        },
    },

    -- Highlight groups
    highlights = {
        current = "Bold", -- Current buffer filename (in last editor window)
        active = "Normal", -- Active buffers visible in other windows
        inactive = "Comment", -- Inactive/hidden buffer filenames
        modified = "DiagnosticWarn", -- Modified/unsaved buffer filenames and dashes
        inactive_dash = "Comment", -- Inactive buffer dashes in collapsed state
        previous = "Search", -- Label for last-accessed buffer (when keymap is registered)
        label = "DiagnosticVirtualTextHint", -- Default label highlight (actions can override via hl option)
        label_minimal = "Visual", -- Labels in collapsed "full" mode
        window_bg = "BentoNormal", -- Menu window background
        page_indicator = "Comment", -- Pagination indicators (● ○ ○ for floating, ❮/❯ for tabline)
        separator = "Normal", -- Separator between buffer components in tabline
    },
})

-- Actions and keymaps are registered via the API (see "Setting Up Keymaps" above)
```

### Options

#### General Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `lock_char` | string | `"🔒"` | Character displayed before locked buffer names |
| `max_open_buffers` | number/nil | `nil` | Maximum number of buffers to keep open (`nil` = unlimited) |
| `buffer_deletion_metric` | string | `"frecency_access"` | Metric used to decide which buffer to delete when limit is reached (see below) |
| `buffer_notify_on_delete` | boolean | `true` | Whether to create a notification via `vim.notify` when a buffer is deleted by the plugin |
| `ordering_metric` | string/nil | `"access"` | Buffer ordering: `nil` (arbitrary), `"access"` (by last access time), or `"edit"` (by last edit time). Most recent first. |
| `map_last_accessed` | boolean | `false` | If `true`, the last-accessed buffer gets a normal filename-based label. If `false` (default), displays the registered keymap as its label. Only applies when a last-buffer keymap is registered. |
| `highlights` | table | See below | Highlight groups for all UI elements |

#### UI Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ui.mode` | string | `"floating"` | UI mode: `"floating"` (sidebar window) or `"tabline"` (horizontal tabline) |

#### Floating UI Options (`ui.floating`)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `position` | string | `"middle-right"` | Menu position: `"top-left"`, `"top-right"`, `"middle-left"`, `"middle-right"`, `"bottom-left"`, `"bottom-right"` |
| `offset_x` | number | `0` | Horizontal offset from position |
| `offset_y` | number | `0` | Vertical offset from position |
| `dash_char` | string | `"─"` | Character for collapsed state lines |
| `border` | string | `"none"` | Border style for the floating window: `"rounded"`, `"single"`, `"double"`, etc. (see :h winborder) |
| `label_padding` | number | `1` | Padding on left/right of labels |
| `minimal_menu` | string/nil | `nil` | Collapsed menu style: `nil` (hidden), `"dashed"` (dash lines), `"filename"` (names only), `"full"` (names + labels) |
| `max_rendered_buffers` | number/nil | `nil` | Maximum buffers to display per page. Pagination is also automatically enabled when buffers exceed available screen height. Uses `min(max_rendered_buffers, available_height)` when set. Navigate pages with `[` and `]` keys. A centered indicator (`● ○ ○`) shows current page. |

#### Tabline UI Options (`ui.tabline`)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `left_page_symbol` | string | `"❮"` | Symbol shown at left edge when previous buffers exist (pagination) |
| `right_page_symbol` | string | `"❯"` | Symbol shown at right edge when more buffers exist (pagination) |
| `separator_symbol` | string | `"|"` | Separator character between buffer components |

### Buffer Deletion Metrics

When `max_open_buffers` is set to a positive value, bento will automatically delete buffers to stay within the limit. The `buffer_deletion_metric` option controls how buffers are prioritized for deletion:

| Metric | Description |
|--------|-------------|
| `"recency_access"` | Delete the buffer that was **accessed** (entered/viewed) least recently. Uses Neovim's built-in `lastused` tracking. |
| `"recency_edit"` | Delete the buffer that was **edited** least recently. Buffers you haven't modified in a while are deleted first. |
| `"frecency_access"` | Delete the buffer with the lowest **access frecency**. This is the default. Frecency combines frequency and recency - buffers you access often and recently score higher and are kept. |
| `"frecency_edit"` | Delete the buffer with the lowest **edit frecency**. Buffers you edit frequently and recently score higher and are kept. |

**Recency** metrics simply look at when the last event occurred. **Frecency** metrics use a decay-based algorithm that considers the entire history of events, giving higher scores to buffers that are both frequently and recently used.

### Highlights

All highlights are configurable under the `highlights` table:

| Key | Default | Description |
|-----|---------|-------------|
| `current` | `"Bold"` | Current buffer filename (in last editor window) |
| `active` | `"Normal"` | Active buffers visible in other windows |
| `inactive` | `"Comment"` | Inactive/hidden buffer filenames |
| `modified` | `"DiagnosticWarn"` | Modified/unsaved buffer filenames and dashes |
| `inactive_dash` | `"Comment"` | Inactive buffer dashes in collapsed state |
| `previous` | `"Search"` | Label for last-accessed buffer (when keymap is registered) |
| `label` | `"DiagnosticVirtualTextHint"` | Default label highlight (actions can override via `hl` option) |
| `label_minimal` | `"Visual"` | Labels in collapsed "full" mode |
| `window_bg` | `"BentoNormal"` | Menu window background (transparent by default) |
| `page_indicator` | `"Comment"` | Pagination indicator: `● ○ ○` in floating UI, `❮`/`❯` symbols in tabline UI |
| `separator` | `"Normal"` | Separator character between buffer components in tabline UI |


## Lua API

```lua
local api = require("bento.api")

-- Keymap registration (recommended for setup)
api.register_expand_key("<YOUR_EXPAND_KEY>")   -- Register key to open/expand menu
api.register_last_buffer_key("<YOUR_LB_KEY>")   -- Register key as label for last-accessed buffer
api.register_collapse_key("<Esc>")  -- Register key to collapse/close menu
api.register_prev_page_key("[")     -- Register key for previous page
api.register_next_page_key("]")     -- Register key for next page

-- Action registration (required - no actions are registered by default)
api.register_action("open", { key = "<CR>", action = api.actions.open, hl = "DiagnosticVirtualTextHint" })
api.register_action("delete", { key = "<BS>", action = api.actions.delete, hl = "DiagnosticVirtualTextError" })
api.set_default_action("open")        -- Set default action for direct label press

-- Built-in action functions (use with register_action)
api.actions.open      -- Opens buffer in current window
api.actions.delete    -- Deletes buffer
api.actions.vsplit    -- Opens buffer in vertical split
api.actions.split     -- Opens buffer in horizontal split
api.actions.lock      -- Toggles lock on buffer

-- Menu control
api.open_menu()           -- Open and expand the menu (convenience function)
api.toggle_menu()         -- Toggle menu open/closed
api.expand_menu()         -- Expand menu to show labels
api.collapse_menu()       -- Collapse menu back to minimal state
api.close_menu()          -- Close menu completely
api.refresh_menu()        -- Refresh menu contents

-- Buffer selection
api.select_buffer(index)  -- Select buffer by index

-- Pagination
-- Floating UI: requires max_rendered_buffers to be set
-- Tabline UI: automatic when buffers exceed screen width
api.next_page()
api.prev_page()

-- Action mode
api.set_action_mode("delete")

-- Buffer locking (protects buffers from automatic deletion)
-- Lock state is persisted across sessions via :mksession
api.toggle_lock()      -- Toggle lock on current buffer
api.toggle_lock(bufnr) -- Toggle lock on specific buffer
api.is_locked()        -- Check if current buffer is locked
api.is_locked(bufnr)   -- Check if specific buffer is locked

-- Close all buffers (with optional exclusions)
-- By default, closes ALL buffers. Pass false to exclude certain buffers.
api.close_all_buffers()                                                     -- Close ALL buffers
api.close_all_buffers({ visible = false })                                  -- Keep visible buffers open
api.close_all_buffers({ locked = false })                                   -- Keep locked buffers open
api.close_all_buffers({ current = false })                                  -- Keep current buffer open
api.close_all_buffers({ visible = false, locked = false, current = false }) -- Keep all protected

-- Command
:BentoToggle
```

## Session support
Buffer metrics (access/edit times) and lock state are automatically persisted across sessions when using Neovim's :mksession and restored on SessionLoadPost. This ensures buffer ordering remains consistent after restarting Neovim with a saved session. Make sure you include "globals" in `sessionoptions`.


## Examples

### Tabline UI

```lua
require("bento").setup({
    ui = {
        mode = "tabline", -- Use tabline instead of floating window
    },
})

-- Register keymaps and actions after setup
local api = require("bento.api")
api.register_expand_key("<YOUR_EXPAND_KEY>")
api.register_last_buffer_key("<YOUR_LB_KEY>")
api.register_collapse_key("<Esc>")
api.register_prev_page_key("[")
api.register_next_page_key("]")

-- Register actions
api.register_action("open", { key = "<CR>", action = api.actions.open })
api.register_action("delete", { key = "<BS>", action = api.actions.delete })
api.set_default_action("open")
```

### Custom Highlighting

```lua
require("bento").setup({
    highlights = {
        current = "Title",
        active = "Normal",
        inactive = "NonText",
        modified = "WarningMsg",
        inactive_dash = "NonText",
        previous = "WarningMsg",
        label = "IncSearch", -- Default label highlight
    },
})
```

### Custom Action Examples

```lua
local api = require("bento.api")

-- Git: Stage current buffer
api.register_action("git_stage", {
    key = "g",
    action = function(_, buf_name)
        vim.cmd("!git add " .. vim.fn.shellescape(buf_name))
    end,
})

-- Copy path to clipboard
api.register_action("copy_path", {
    key = "y",
    action = function(_, buf_name)
        vim.fn.setreg("+", buf_name)
    end,
})
```

### Using the Lua API for Advanced Behavior

For more complex behavior, use the Lua API functions directly instead of (or in addition to) the keymap registration functions:

```lua
-- Open menu automatically when creating a new split
vim.api.nvim_create_autocmd("WinNew", {
    callback = function()
        vim.defer_fn(function()
            require("bento.api").open_menu()
        end, 50)
    end,
})

-- Custom keymap with additional logic
vim.keymap.set("n", "<YOUR_EXPAND_KEY>", function()
    local api = require("bento.api")
    -- Only open if we have more than one buffer
    if #vim.fn.getbufinfo({ buflisted = 1 }) > 1 then
        api.open_menu()
    else
        print("Only one buffer open")
    end
end, { desc = "Open Bento menu" })
```

## Acknowledgments & inspiration

- [buffer-sticks.nvim](https://github.com/ahkohd/buffer-sticks.nvim) by [`ahkohd`](https://github.com/ahkohd): this plugin inspired some of the ideas implemented in `bento` (e.g., the dashed menu). You should also check out this plugin, it's very good and it pursues solutions to many of the same problems.

- [buffer_manager.nvim](https://github.com/j-morano/buffer_manager.nvim) by [`j-morano`](https://github.com/j-morano): I took architectural ideas from this plugin initially, although at this point the differences may be too large to notice.
