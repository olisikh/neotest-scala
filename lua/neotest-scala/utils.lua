local Path = require("plenary.path")

local M = {}

--- Strip quotes from the test position
---@param position neotest.Position
---@return string
function M.get_position_name(position)
    if position.type == "test" then
        return (position.name:gsub('"', ""))
    end
    return position.name
end

--- Check if test has nested tests
---@param test neotest.Tree
---@return boolean
function M.has_nested_tests(test)
    return #test:children() > 0
end

--- Find namespace type parent node
---@param tree neotest.Tree
---@param type string
---@param down boolean
---@return neotest.Tree|nil
function M.find_node(tree, type, down)
    if tree:data().type == type then
        return tree
    elseif not down then
        local p = tree:parent()
        if p then
            return M.find_node(p, type, down)
        else
            return nil
        end
    else
        for _, child in tree:iter_nodes() do
            if child:data().type == type then
                return child
            end
        end
    end
end

--- Get package name from top of file
---@param path string
---@return string
function M.get_package_name(path)
    local lib = require("neotest.lib")
    local success, lines = pcall(lib.files.read_lines, path)
    if not success then
        return ""
    end
    local line = lines[1]
    if vim.startswith(line, "package") then
        return vim.split(line, " ")[2] .. "."
    end
    return ""
end

--- Get file name from path
---@param path string
---@return string
function M.get_file_name(path)
    local parts = vim.split(path, Path.path.sep)
    return parts[#parts]
end

--- Trim string
---@param s string
---@return string
function M.string_trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

--- Normalize spaces
---@param s string
---@return string
function M.string_despace(s)
    return (s:gsub("%s+", " "))
end

--- Remove quotes
---@param s string
---@return string
function M.string_remove_dquotes(s)
    return (s:gsub('^s*"', ""):gsub('"$', ""))
end

--- Remove ANSI
---@param s string
---@return string
function M.string_remove_ansi(s)
    return (s:gsub("%[%d*;?%d*m", ""))
end

--- Unescape XML entities
---@param s string
---@return string
function M.string_unescape_xml(s)
    local xml_escapes = {
        ["&quot;"] = '"',
        ["&apos;"] = "'",
        ["&amp;"] = "&",
        ["&lt;"] = "<",
        ["&gt;"] = ">",
    }

    for esc, char in pairs(xml_escapes) do
        s = string.gsub(s, esc, char)
    end

    return s
end

return M
