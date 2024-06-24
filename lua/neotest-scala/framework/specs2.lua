local utils = require("neotest-scala.utils")

---@class neotest-scala.Framework
local M = {}

---Get test ID from the test line output.
---@param output string
---@return string
local function get_test_id(output)
    local words = vim.split(output, " ", { trimempty = true })
    -- Strip the test success/failure indicator
    table.remove(words, 1)
    return table.concat(words, " ")
end

---Sanitizes the line with error message removing all that is not useful to show in the diagnostic
---@param line any
---@return unknown
local function sanitize_error(line)
    return line:match("^(.*)%s%(.*:%d+%)$")
end

---Get line number where error test error was recorded
---@param line string
---@return number
local function get_error_lnum(line)
    local line_num = line:match("^.*:(%d+)%)$")
    if line_num ~= nil then
        local ok, value = pcall(tonumber, line_num)
        if ok then
            line_num = value - 1
        end
    end
    return line_num
end

-- Get test results from the test output.
---@param output_lines string[]
---@return table<string, string>
function M.get_test_results(output_lines)
    local test_results = {}
    local test_id = nil

    for _, line in ipairs(output_lines) do
        line = vim.trim(utils.strip_bloop_error_prefix(utils.strip_sbt_log_prefix(utils.strip_ansi_chars(line))))

        -- look for the succeeded tests they start with + prefix
        if vim.startswith(line, "+") then
            test_id = get_test_id(line)
            test_results[test_id] = { status = TEST_PASSED }

            --look for failed tests they start with x prefix
        elseif vim.startswith(line, "x") then
            test_id = get_test_id(line)
            if test_id ~= nil then
                test_results[test_id] = { status = TEST_FAILED }
            end

            --look for test failures, and make diagnostic messages
        else
            local sanitized = sanitize_error(line)
            local error_lnum = get_error_lnum(line)

            if sanitized and error_lnum then
                test_results[test_id].errors = {
                    {
                        message = sanitized,
                        line = error_lnum,
                    },
                }
            end
        end
    end

    return test_results
end

local function find_parent_file_node(tree)
    local parent = tree:parent()
    if parent ~= nil and parent:data().type ~= "file" then
        return find_parent_file_node(parent)
    else
        return parent
    end
end

local function resolve_test_name(file_node)
    assert(
        file_node:data().type == "file",
        "[neotest-scala]: Tree must be of type 'file', but got: " .. file_node:data().type
    )

    local test_suites = {}
    for _, child in file_node:iter_nodes() do
        if child:data().type == "namespace" then
            table.insert(test_suites, child:data().name)
        end
    end

    if test_suites then
        local package = utils.get_package_name(file_node:data().path)
        if #test_suites == 1 then
            -- run individual spec
            return package .. test_suites[1]
        else
            -- otherwise run tests for whole package
            return package .. "*"
        end
    end
end

local function build_test_namespace(tree)
    local type = tree:data().type

    if type == "file" then
        return resolve_test_name(tree)
    elseif type == "dir" then
        return "*"
    else
        return resolve_test_name(find_parent_file_node(tree))
    end
end

--- Builds a command for running tests for the framework.
---@param runner string
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
function M.build_command(runner, project, tree, name, extra_args)
    local test_namespace = build_test_namespace(tree)

    local command = nil

    if runner == "bloop" then
        local full_test_path
        if not test_namespace then
            full_test_path = {}
        elseif tree:data().type ~= "test" then
            full_test_path = { "-o", test_namespace }
        else
            full_test_path = { "-o", test_namespace, "--", "-z", name }
        end
        command = vim.tbl_flatten({ "bloop", "test", extra_args, project, full_test_path })
    elseif not test_namespace then
        command = vim.tbl_flatten({ "sbt", extra_args, project .. "/test" })
    else
        local test_path = ""
        if tree:data().type == "test" then
            test_path = ' -- ex "' .. name .. '"'
        end

        command = vim.tbl_flatten({ "sbt", extra_args, project .. "/testOnly " .. test_namespace .. test_path })
    end

    vim.print("Running test command: " .. vim.inspect(command))

    return command
end

-- Get test results from the test output.
---@param junit_test table<string, string>
---@param position neotest.Position
---@return string|nil
function M.match_func(junit_test, position)
    vim.print(junit_test.name .. " matches " .. position.id)

    -- local res = nil
    --
    -- for test_id, result in pairs(test_results) do
    --     if position_id:match(test_id) then
    --         res = result
    --         break
    --     end
    -- end

    return false
end

---@return neotest-scala.Framework
return M
