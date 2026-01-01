<div align="center">

![logo](https://github.com/user-attachments/assets/2105a347-4218-4afb-b20b-74fcbcff4b5a)

# 🍱 bento.nvim

</div>

A minimalist, efficient, and extensible buffer manager for Neovim.

## Features

- **Transparent sidebar** with collapsed (dashes only or completely hidden) and expanded (labels + names) states
- **Smart label assignment** based on filenames for quick buffer switching
- **Last accessed buffer** quick switch (press `;` twice)
- **Extensible action system** with visual feedback (open, delete, custom actions)
- **Visual indicators** for current, active, and inactive buffers
- **Buffer limit enforcement** with LRU deletion (optional)
- **Auto-collapse** on selection and cursor movement
- **No dependencies**

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
- `<C-o>` → Enter open mode, then select buffer
- `<C-d>` → Enter delete mode, then select buffer
- `ESC` → Collapse back to dashes

## Visual States

**Collapsed (default):** Shows dashes only, or nothing if `config.show_minimal_menu = false`
- `──` = Active buffer (visible)
- ` ─` = Inactive buffer (hidden)

**Expanded:** Shows buffer names + labels (right-aligned)
- **Bold** = Current buffer
- Normal = Active in other windows
- *Dimmed* = Inactive
- `;` label = Last accessed buffer

## Actions

Actions change label colors for visual feedback. Built-in actions:
- **Open** (`<C-o>`): Opens selected buffer (default yellow labels)
- **Delete** (`<C-d>`): Deletes selected buffer (red labels)

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
    offset_y = 0, -- Vertical offset from center
    dash_char = "─", -- Character for collapsed dashes
    label_padding = 1, -- Padding around labels
    max_open_buffers = -1, -- Max buffers (-1 = unlimited)
    default_action = "open", -- Action when pressing label directly
    show_minimal_menu = true, -- Show the dashed collapsed menu

    -- Highlight groups
    hl_filename = "Bold", -- Current buffer filename
    hl_inactive = "Comment", -- Inactive buffer dashes
    hl_open = "Search", -- Open action labels
    hl_delete = "ErrorMsg", -- Delete action labels

    -- Custom actions
    actions = {},
})
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `main_keymap` | string | `";"` | Primary key for menu toggle and expand |
| `offset_y` | number | `0` | Vertical offset from center |
| `dash_char` | string | `"─"` | Character for collapsed state lines |
| `label_padding` | number | `1` | Padding on left/right of labels |
| `max_open_buffers` | number | `-1` | Maximum number of buffers to keep open (`-1` = unlimited) |
| `hl_filename` | string | `"Bold"` | Highlight group for filenames |
| `hl_inactive` | string | `"Comment"` | Highlight group for inactive buffer dashes |
| `hl_open` | string | `"Search"` | Highlight group for open mode labels |
| `hl_delete` | string | `"ErrorMsg"` | Highlight group for delete mode labels |
| `actions` | table | Built-in actions | Action definitions (see Actions section) |
| `default_action` | string | `"open"` | Default action mode when menu expands |
| `show_minimal_menu` | boolean | `true` | Whether to show the dashed collapsed menu (`true`) or to show nothing when collapsed (`false`) |


## Lua API

```lua
-- Menu control
require("bento.ui").toggle_menu()
require("bento.ui").expand_menu()
require("bento.ui").collapse_menu()
require("bento.ui").close_menu()
require("bento.ui").refresh_menu()

-- Actions
require("bento.ui").set_action_mode("delete")
require("bento.ui").select_buffer(index)

-- Command
:BentoToggle
```

## Examples

### Custom Highlighting

```lua
require("bento").setup({
    hl_open = "IncSearch",
    hl_delete = "DiagnosticError",
})
```

### Override Built-in Actions

```lua
require("bento").setup({
    actions = {
        open = {
            key = "<CR>", -- Change from default <C-o>
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

    -- Open in split
    split = {
        key = "s",
        action = function(buf_id)
            vim.cmd("split | buffer " .. buf_id)
        end,
    },
}
```

## Acknowledgments & inspiration

- [buffer_manager.nvim](https://github.com/j-morano/buffer_manager.nvim) by [`j-morano`](https://github.com/j-morano)
- [buffer-sticks.nvim](https://github.com/ahkohd/buffer-sticks.nvim) by [`ahkohd`](https://github.com/ahkohd)
