--- Bento.nvim plugin entry point
--- Prevents multiple loading of the plugin

if vim.g.bento_loaded then
    return
end

--- Flag to indicate the plugin has been loaded
vim.g.bento_loaded = 1
