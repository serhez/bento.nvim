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
- **Extensible action system** with visual feedback (built-in actions: open, delete, split, lock)
- **Customizable UI** with multiple collapsed states (dashes, filenames, full, or hidden) and placement options
- **Smart one-char label assignment** based on filenames for quick buffer switching
- **Last accessed/edited buffer quick switch** (press `;` twice)
- **Buffer limit enforcement** with configurable deletion metrics (optional)
- **Buffer locking** to protect important buffers from automatic deletion (persisted across sessions)
- **Pagination** for large buffer lists (automatic when exceeding screen space, or configurable via `max_rendered_buffers`)
- **Configurable buffer ordering** by access time, edit time, filename, or directory

## Installation

Neovim 0.9.0+ required. Works with any plugin manager:

```lua
-- lazy.nvim
{ "serhez/bento.nvim", opts = {} }

-- packer.nvim
use({ "serhez/bento.nvim", config = function() require("bento").setup() end })
```

## Quick Start

Works out of the box with defaults. The main keymap is `;`:

- `;` once → Open menu (collapsed, shows dashes)
- `;` twice → Expand menu (shows labels and names) / Switch to last accessed buffer
- Label key → Open that buffer
- `<CR>` → Enter open mode, then select buffer
- `<BS>` → Enter delete mode, then select buffer
- `|` → Enter vertical split mode, then select buffer
- `_` → Enter horizontal split mode, then select buffer
- `*` → Toggle lock on selected buffer (protected from auto-deletion)
- `[` / `]` → Previous / next page (floating: when `max_rendered_buffers` is set; tabline: when buffers exceed screen width)
- `ESC` → Collapse back to dashes

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
- `;` label = Last accessed buffer

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

Actions change label colors for visual feedback. Built-in actions:
- **Open** (`<CR>`): Opens selected buffer in current window
- **Delete** (`<BS>`): Deletes selected buffer
- **Vertical Split** (`|`): Opens selected buffer in a vertical split
- **Horizontal Split** (`_`): Opens selected buffer in a horizontal split
- **Lock** (`*`): Toggles lock on selected buffer (locked buffers are protected from automatic deletion)

### Custom Actions

```lua
require("bento").setup({
    actions = {
        git_stage = {
            key = "g",
            hl = "DiffAdd", -- Optional: custom label color
            action = function(buf_id, buf_name)
                vim.cmd("!git add " .. vim.fn.shellescape(buf_name))
            end,
        },
    },
})
```

Action fields: `key` (required), `action` (required), `hl` (optional highlight group)

## Configuration

All options with defaults:

```lua
require("bento").setup({
    main_keymap = ";", -- Main toggle/expand key
    lock_char = "🔒", -- Character shown before locked buffer names
    max_open_buffers = nil, -- Max buffers (nil = unlimited)
    buffer_deletion_metric = "frecency_access", -- Metric for buffer deletion (see below)
    buffer_notify_on_delete = true, -- Notify when deleting a buffer (false for silent deletion)
    ordering_metric = "access", -- Buffer ordering: nil (insertion order), "access", "edit", "filename", or "directory"
    locked_first = false, -- Sort locked buffers to the top
    default_action = "open", -- Action when pressing label directly
    map_last_accessed = false, -- Whether to map a key to the last accessed buffer (besides main_keymap)

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
        previous = "Search", -- Label for previous buffer (main_keymap label)
        label_open = "DiagnosticVirtualTextHint", -- Labels in open action mode
        label_delete = "DiagnosticVirtualTextError", -- Labels in delete action mode
        label_vsplit = "DiagnosticVirtualTextInfo", -- Labels in vertical split mode
        label_split = "DiagnosticVirtualTextInfo", -- Labels in horizontal split mode
        label_lock = "DiagnosticVirtualTextWarn", -- Labels in lock action mode
        label_minimal = "Visual", -- Labels in collapsed "full" mode
        window_bg = "BentoNormal", -- Menu window background
        page_indicator = "Comment", -- Pagination indicators (● ○ ○ for floating, ❮/❯ for tabline)
        separator = "Normal", -- Separator between buffer components in tabline
    },

    -- Custom actions
    actions = {},
})
```

### Options

#### General Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `main_keymap` | string | `";"` | Primary key for menu toggle and expand |
| `lock_char` | string | `"🔒"` | Character displayed before locked buffer names |
| `max_open_buffers` | number/nil | `nil` | Maximum number of buffers to keep open (`nil` = unlimited) |
| `buffer_deletion_metric` | string | `"frecency_access"` | Metric used to decide which buffer to delete when limit is reached (see below) |
| `buffer_notify_on_delete` | boolean | `true` | Whether to create a notification via `vim.notify` when a buffer is deleted by the plugin |
| `ordering_metric` | string/nil | `"access"` | Buffer ordering: `nil` (insertion order), `"access"` (by last access time, most recent first), `"edit"` (by last edit time, most recent first), `"filename"` (alphabetical by filename), or `"directory"` (alphabetical by full path). |
| `locked_first` | boolean | `false` | If true, locked buffers are always sorted to the top of the list. |
| `default_action` | string | `"open"` | Default action mode when menu expands |
| `map_last_accessed` | boolean | `false` | If true, maps a key based on filename to the last accessed buffer (like all other buffers). If false it is only mapped to main_keymap. |
| `highlights` | table | See below | Highlight groups for all UI elements |
| `actions` | table | Built-in actions | Action definitions (see Actions section) |

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
| `previous` | `"Search"` | Label for previous buffer (the `main_keymap` label) |
| `label_open` | `"DiagnosticVirtualTextHint"` | Labels in open action mode |
| `label_delete` | `"DiagnosticVirtualTextError"` | Labels in delete action mode |
| `label_vsplit` | `"DiagnosticVirtualTextInfo"` | Labels in vertical split mode |
| `label_split` | `"DiagnosticVirtualTextInfo"` | Labels in horizontal split mode |
| `label_lock` | `"DiagnosticVirtualTextWarn"` | Labels in lock action mode |
| `label_minimal` | `"Visual"` | Labels in collapsed "full" mode |
| `window_bg` | `"BentoNormal"` | Menu window background (transparent by default) |
| `page_indicator` | `"Comment"` | Pagination indicator: `● ○ ○` in floating UI, `❮`/`❯` symbols in tabline UI |
| `separator` | `"Normal"` | Separator character between buffer components in tabline UI |


## Lua API

```lua
-- Menu control
require("bento.ui").toggle_menu()
require("bento.ui").expand_menu()
require("bento.ui").collapse_menu()
require("bento.ui").close_menu()
require("bento.ui").refresh_menu()
require("bento.ui").cycle_minimal_menu() -- Cycle through minimal menu modes (nil -> "dashed" -> "filename" -> "full")

-- Pagination
-- Floating UI: requires max_rendered_buffers to be set
-- Tabline UI: automatic when buffers exceed screen width
require("bento.ui").next_page()
require("bento.ui").prev_page()

-- Actions
require("bento.ui").set_action_mode("delete")
require("bento.ui").select_buffer(index)

-- Buffer locking (protects buffers from automatic deletion)
-- Lock state is persisted across sessions via :mksession
require("bento").toggle_lock()      -- Toggle lock on current buffer
require("bento").toggle_lock(bufnr) -- Toggle lock on specific buffer
require("bento").is_locked()        -- Check if current buffer is locked
require("bento").is_locked(bufnr)   -- Check if specific buffer is locked

-- Close all buffers (with optional exclusions)
-- By default, closes ALL buffers. Pass false to exclude certain buffers.
require("bento").close_all_buffers()                                                     -- Close ALL buffers
require("bento").close_all_buffers({ visible = false })                                  -- Keep visible buffers open
require("bento").close_all_buffers({ locked = false })                                   -- Keep locked buffers open
require("bento").close_all_buffers({ current = false })                                  -- Keep current buffer open
require("bento").close_all_buffers({ visible = false, locked = false, current = false }) -- Keep all protected

-- Command
:BentoToggle
:BentoCycleMinimalMenu  -- Cycle through minimal menu modes (floating UI only)
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
    -- Tabline is always visible, showing buffers horizontally
    -- Press main_keymap to expand and activate keymaps
})
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
        label_open = "IncSearch",
        label_delete = "DiagnosticError",
    },
})
```

### Override Built-in Actions

```lua
require("bento").setup({
    actions = {
        open = {
            key = "<C-o>", -- Change from default <CR>
            hl = "String",
            action = function(buf_id, buf_name)
                vim.cmd("buffer " .. buf_id)
                require("bento.ui").collapse_menu()
            end,
        },
    },
})
```

### Custom Action Examples

```lua
actions = {
    -- Git
    git_stage = {
        key = "g",
        action = function(_, buf_name)
            vim.cmd("!git add " .. vim.fn.shellescape(buf_name))
        end,
    },

    -- Copy path
    copy_path = {
        key = "y",
        action = function(_, buf_name)
            vim.fn.setreg("+", buf_name)
        end,
    },
}
```

### Custom Display Names
```lua
  local butils = require("bento.utils")

  -- Change from ~/home/yak/file.lua -> ~/h/y/file.lua
  -- by default this is displayed as file.lua
  butils.get_display_names = function(paths)
    local display_names = {}
    for _, p in ipairs(paths) do
      display_names[p] = vim.fn.pathshorten(vim.fn.fnamemodify(p, ":~:."), 1)
    end
    return  display_names
  end
  require("bento").setup(opts)
```

## Acknowledgments & inspiration

- [buffer-sticks.nvim](https://github.com/ahkohd/buffer-sticks.nvim) by [`ahkohd`](https://github.com/ahkohd): this plugin inspired some of the ideas implemented in `bento` (e.g., the dashed menu). You should also check out this plugin, it's very good and it pursues solutions to many of the same problems.

- [buffer_manager.nvim](https://github.com/j-morano/buffer_manager.nvim) by [`j-morano`](https://github.com/j-morano): I took architectural ideas from this plugin initially, although at this point the differences may be too large to notice.
