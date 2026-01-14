--- Bento.nvim utility functions
--- @module bento.utils

local M = {}

--- Extract the filename from a full file path
--- @param file string Full file path
--- @return string Filename without directory
function M.get_file_name(file)
    return file:match("[^/\\]*$")
end

--- Split a path into components (directories + filename)
--- @param path string File path
--- @return string[] Path components
function M.split_path(path)
    local components = {}
    for part in string.gmatch(path, "[^/\\]+") do
        table.insert(components, part)
    end
    return components
end

--- Shorten home directory to ~
--- @param path string File path
--- @return string Path with home directory shortened
local function shorten_home(path)
    local home = os.getenv("HOME")
    if home and path:sub(1, #home) == home then
        return "~" .. path:sub(#home + 1)
    end
    return path
end

--- Compute minimal distinguishing display names for a list of file paths
--- Returns a table mapping each path to its minimal display name
--- @param paths string[] List of file paths
--- @return table<string, string> Mapping of path to display name
function M.get_display_names(paths)
    local display_names = {}

    local by_filename = {}
    for _, path in ipairs(paths) do
        local filename = M.get_file_name(path)
        if not by_filename[filename] then
            by_filename[filename] = {}
        end
        table.insert(by_filename[filename], path)
    end

    for filename, group in pairs(by_filename) do
        if #group == 1 then
            display_names[group[1]] = filename
        else
            local path_components = {}
            for _, path in ipairs(group) do
                path_components[path] = M.split_path(path)
            end

            for _, path in ipairs(group) do
                local components = path_components[path]
                local num_components = #components

                for depth = 1, num_components do
                    local candidate_parts = {}
                    for i = num_components - depth + 1, num_components do
                        table.insert(candidate_parts, components[i])
                    end
                    local candidate = table.concat(candidate_parts, "/")

                    local is_unique = true
                    for _, other_path in ipairs(group) do
                        if other_path ~= path then
                            local other_components = path_components[other_path]
                            local other_num = #other_components

                            if other_num >= depth then
                                local other_parts = {}
                                for i = other_num - depth + 1, other_num do
                                    table.insert(
                                        other_parts,
                                        other_components[i]
                                    )
                                end
                                local other_candidate =
                                    table.concat(other_parts, "/")

                                if candidate == other_candidate then
                                    is_unique = false
                                    break
                                end
                            end
                        end
                    end

                    if is_unique then
                        display_names[path] = shorten_home(candidate)
                        break
                    end
                end

                if not display_names[path] then
                    display_names[path] = shorten_home(path)
                end
            end
        end
    end

    return display_names
end

--- Check if a buffer is valid (listed and has a name)
--- @param buf_id number Buffer ID
--- @param buf_name string Buffer name
--- @return boolean
function M.buffer_is_valid(buf_id, buf_name)
    return vim.fn.buflisted(buf_id) == 1 and buf_name ~= ""
end

--- Recursively merge t2 into t1
--- @param t1 table Target table
--- @param t2 table Source table
--- @return nil
local function merge_table_impl(t1, t2)
    for k, v in pairs(t2) do
        if type(v) == "table" and type(t1[k]) == "table" then
            merge_table_impl(t1[k], v)
        else
            t1[k] = v
        end
    end
end

--- Deep merge multiple tables
--- @vararg table Tables to merge
--- @return table Merged table
function M.merge_tables(...)
    local out = {}
    for i = 1, select("#", ...) do
        merge_table_impl(out, select(i, ...))
    end
    return out
end

return M
