local utils = require("neotest-scala.utils")

local M = {}

---Check if file is a specs2 TextSpec (contains s2""" syntax)
---@param file_content string
---@return boolean
function M.is_textspec(file_content)
    return file_content:match('s2"""') ~= nil
end

---Parse specs2 TextSpec content and extract tests
---@param content string
---@return table[] Array of {name = string, path = string, line = number, ref = string}
local function parse_textspec(content)
    local tests = {}
    local lines = vim.split(content, "\n")

    -- Find the s2""" block
    local in_block = false
    local block_start = 0
    local indent_stack = {}

    for i, line in ipairs(lines) do
        local trimmed = line:match("^%s*(.*)")

        -- Detect s2""" start
        if not in_block and line:match('s2"""') then
            in_block = true
            block_start = i
        -- Detect s2""" end (triple quote at start of block content)
        elseif in_block and i > block_start and trimmed:match('^"""') then
            in_block = false
        -- Process lines inside the block
        elseif in_block and trimmed ~= "" then
            local indent = #line - #trimmed

            -- Track section hierarchy based on indentation
            while #indent_stack > 0 and indent <= indent_stack[#indent_stack].indent do
                table.remove(indent_stack)
            end

            -- Check if this line contains a test reference ($e1, $test, etc.)
            local test_name, ref = trimmed:match("^(.-)%s*(%$[%w_]+)%s*$")

            if test_name and ref then
                -- Build hierarchical path
                local path_parts = {}
                for _, item in ipairs(indent_stack) do
                    table.insert(path_parts, item.name)
                end
                table.insert(path_parts, (test_name:gsub("^%s*", ""):gsub("%s*$", "")))

                local full_path = table.concat(path_parts, "::")

                table.insert(tests, {
                    name = test_name:gsub("^%s*", ""):gsub("%s*$", ""),
                    path = full_path,
                    line = i,
                    ref = ref:gsub("%$", ""), -- Remove $ prefix
                })
            else
                -- This is a section header
                table.insert(indent_stack, {
                    name = trimmed:gsub("^%s*", ""):gsub("%s*$", ""),
                    indent = indent,
                })
            end
        end
    end

    return tests
end

---Find the line number of a TextSpec method definition
---@param content string
---@param ref string The method reference (e.g., "e1", "test")
---@return number|nil
local function find_method_line(content, ref)
    local lines = vim.split(content, "\n")

    for i, line in ipairs(lines) do
        -- Match patterns like: def e1 = ..., def e1: Type = ..., def e1 { ... }
        if line:match("^%s*def%s+" .. ref .. "%s*[=:{]") then
            return i
        end
    end

    return nil
end

---Build neotest positions tree for TextSpec tests
---@class neotest-scala.Specs2TextSpecDiscoverOpts
---@field path string Path to the file
---@field content string File content

---@param opts neotest-scala.Specs2TextSpecDiscoverOpts
---@return neotest.Tree|nil
function M.discover_positions(opts)
    local path = opts.path
    local content = opts.content
    local tests = parse_textspec(content)
    local package_name = utils.get_package_name(path) or ""

    -- Find the class/object name
    local class_name = content:match("class%s+([%w_]+)%s*extends") or content:match("object%s+([%w_]+)%s*extends")
    if not class_name then
        class_name = "Unknown"
    end

    if #tests == 0 then
        return nil
    end

    local lines = vim.split(content, "\n")
    local total_lines = #lines

    -- Find the class definition line number
    local class_line = 1
    for i, line in ipairs(lines) do
        if line:match("class%s+" .. class_name) or line:match("object%s+" .. class_name) then
            class_line = i
            break
        end
    end

    -- Build test positions as nested lists for Tree.from_list
    local test_list = {}
    for _, test in ipairs(tests) do
        local method_line = find_method_line(content, test.ref)
        local line_num = method_line and (method_line - 1) or (test.line - 1)

        table.insert(test_list, {
            {
                id = package_name .. class_name .. "." .. test.name,
                name = test.name,
                path = path,
                type = "test",
                range = { line_num, 0, line_num, 0 },
                ---@type neotest-scala.PositionExtra
                extra = {
                    textspec_path = test.path,
                },
            },
        })
    end

    -- Build the tree structure as nested lists
    local tree_list = {
        {
            id = path,
            name = vim.fn.fnamemodify(path, ":t"),
            path = path,
            type = "file",
            range = { 0, 0, total_lines - 1, 0 },
        },
        vim.list_extend({
            {
                id = package_name .. class_name,
                name = class_name,
                path = path,
                type = "namespace",
                range = { class_line - 1, 0, total_lines - 1, 0 },
            },
        }, test_list),
    }

    return require("neotest.types").Tree.from_list(tree_list, function(pos)
        return pos.id
    end)
end

---Check if a namespace contains TextSpec tests
---@param ns_node neotest.Tree
---@return boolean
function M.is_textspec_namespace(ns_node)
    for _, test_node in ns_node:iter_nodes() do
        local pos = test_node:data()
        if pos.extra and pos.extra.textspec_path then
            return true
        end
    end
    return false
end

---Build namespace for TextSpec (different report path format)
---@param ns_node neotest.Tree
---@param report_prefix string
---@return table
function M.build_namespace(ns_node, report_prefix)
    local data = ns_node:data()
    local namespace = {
        path = data.path,
        namespace = data.id,
        -- TextSpec: id already includes package, don't prepend package_name
        report_path = report_prefix .. "TEST-" .. data.id .. ".xml",
        tests = {},
    }
    for _, n in ns_node:iter_nodes() do
        if n:data().type == "test" then
            table.insert(namespace["tests"], n)
        end
    end
    return namespace
end

return M
