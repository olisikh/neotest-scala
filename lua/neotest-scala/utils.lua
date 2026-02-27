local lib = require("neotest.lib")
local sep = package.config:sub(1, 1)

local M = {}
local INTERPOLATION_MARKER = "__NEOTEST_SCALA_INTERPOLATION__"

--- Strip quotes from the test position
---@param position neotest.Position
---@return string
function M.get_position_name(position)
    if position.type == "test" then
        local name = position.name
        local interpolator = name:match("^([%a_][%w_]*)\"")
        if interpolator then
            name = name:gsub("^" .. interpolator, "", 1)
        end
        return (name:gsub('"', ""))
    end
    return position.name
end

---@param value string
---@return boolean
function M.is_interpolated_string(value)
    return value:find("%${[^}]+}") ~= nil or value:find("%$[%a_][%w_]*") ~= nil
end

---@param value string
---@param opts? { anchor_start?: boolean, anchor_end?: boolean }
---@return string|nil
local function build_interpolation_pattern(value, opts)
    local templated = value:gsub("%${[^}]+}", INTERPOLATION_MARKER):gsub("%$[%a_][%w_]*", INTERPOLATION_MARKER)
    if not templated:find(INTERPOLATION_MARKER, 1, true) then
        return nil
    end

    local escaped_marker = vim.pesc(INTERPOLATION_MARKER)
    local escaped_template = vim.pesc(templated):gsub(escaped_marker, ".*")

    local anchor_start = not opts or opts.anchor_start ~= false
    local anchor_end = not opts or opts.anchor_end ~= false
    return (anchor_start and "^" or "") .. escaped_template .. (anchor_end and "$" or "")
end

---@param actual string
---@param expected string
---@param opts? { anchor_start?: boolean, anchor_end?: boolean }
---@return boolean
function M.matches_with_interpolation(actual, expected, opts)
    if actual == expected then
        return true
    end

    local interpolation_pattern = build_interpolation_pattern(expected, opts)
    if not interpolation_pattern then
        return false
    end

    return actual:match(interpolation_pattern) ~= nil
end

---@param namespace table|nil
---@param index integer
---@return boolean
function M.is_junit_result_claimed(namespace, index)
    if not namespace then
        return false
    end
    return namespace._claimed_junit_results and namespace._claimed_junit_results[index] == true or false
end

---@param namespace table|nil
---@param index integer
function M.claim_junit_result(namespace, index)
    if not namespace then
        return
    end
    namespace._claimed_junit_results = namespace._claimed_junit_results or {}
    namespace._claimed_junit_results[index] = true
end

--- Check if test has nested tests
---@param test neotest.Tree
---@return boolean
function M.has_nested_tests(test)
    return #test:children() > 0
end

---Extract the highest line number for the given file from stacktrace
---ScalaTest stacktraces have multiple file references (class def, test method, etc.)
---We want the highest line number which corresponds to the actual test assertion
---@param stacktrace string
---@param file_name string
---@return number|nil
function M.extract_line_number(stacktrace, file_name)
    local max_line_num = nil
    local pattern = "%(" .. file_name .. ":(%d+)%)"

    for line_num_str in string.gmatch(stacktrace, pattern) do
        local line_num = tonumber(line_num_str)
        if not max_line_num or line_num > max_line_num then
            max_line_num = line_num
        end
    end

    return max_line_num and (max_line_num - 1) or nil
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
---@return string|nil
function M.get_package_name(path)
    local success, lines = pcall(lib.files.read_lines, path)
    if not success then
        return nil
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
    local parts = vim.split(path, sep)
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

--- Remove ANSI escape sequences
---@param s string
---@return string
function M.string_remove_ansi(s)
    -- Remove ESC[ followed by any parameters and a letter (standard ANSI sequences)
    s = s:gsub("\27%[[%d;]*[a-zA-Z]", "")
    -- Remove any remaining ESC characters
    s = s:gsub("\27", "")
    -- Remove bracket sequences without ESC (like [32m)
    s = s:gsub("%[[%d;]+[a-zA-Z]", "")
    return s
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

--- Build position ID from position and parents (shared across frameworks)
---@param position neotest.Position
---@param parents neotest.Position[]
---@return string
function M.build_position_id(position, parents)
    local result = {}

    for _, parent in ipairs(parents) do
        if parent.type == "namespace" then
            table.insert(result, M.get_package_name(parent.path) .. parent.name)
        elseif parent.type ~= "dir" and parent.type ~= "file" then
            table.insert(result, M.get_position_name(parent))
        end
    end

    table.insert(result, M.get_position_name(position))

    return table.concat(result, ".")
end

return M
