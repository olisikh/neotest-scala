local utils = require("neotest-scala.utils")

---@class neotest-scala.Framework
local M = {}

---Get test ID from the test line output.
---@param output string
---@return string
local function strip_prefix_symbol(output)
    local words = vim.split(output, " ", { trimempty = true })
    -- Strip the test success/failure indicator
    table.remove(words, 1)
    return table.concat(words, " ")
end

local function append_test_result(results, test_result, test_error)
    if test_result then
        if test_error then
            test_result.errors = { test_error }
        end

        results[test_result.test_id] = {
            status = test_result.status,
            errors = test_result.errors,
        }
    end
end

-- Get test results from the test output.
---@param output_lines string[]
---@return table<string, string>
function M.get_test_results(output_lines)
    local test_results = {}
    local test_result = nil
    local test_error = nil

    for _, line in ipairs(output_lines) do
        line = vim.trim(utils.strip_bloop_error_prefix(utils.strip_sbt_log_prefix(utils.strip_ansi_chars(line))))

        -- look for the succeeded tests they start with + prefix
        if vim.startswith(line, "+") then
            append_test_result(test_results, test_result, test_error)

            test_result = {
                test_id = strip_prefix_symbol(line),
                status = TEST_PASSED,
            }

            --look for failed tests they start with x prefix
        elseif vim.startswith(line, "-") then
            append_test_result(test_results, test_result, test_error)

            test_result = {
                test_id = strip_prefix_symbol(line),
                status = TEST_FAILED,
            }

            --look for test failures, and make diagnostic messages
        elseif test_result and vim.startswith(line, "✗") then
            local sanitized = strip_prefix_symbol(line)

            if sanitized then
                test_error = { message = sanitized }
            end
        elseif test_error and line:match("^at /.*%.scala:(%d+)$") then
            local line_num = line:match("^at /.*%.scala:(%d+)$")
            local ok, result = pcall(tonumber, line_num)
            if ok then
                test_error.line = result - 1
            end
        elseif line:match("%d+ tests passed. %d+ tests failed. %d+ tests ignored.") then
            append_test_result(test_results, test_result, test_error)
            break
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
            test_path = ' -- -t "' .. name .. '"'
        end

        command = vim.tbl_flatten({ "sbt", extra_args, project .. "/testOnly " .. test_namespace .. test_path })
    end

    vim.print("Running test command: " .. vim.inspect(command))

    return command
end

-- ---Get test results from the test output.
-- ---@param test_results table<string, string>
-- ---@param position_id string
-- ---@return string|nil
-- function M.match_func(test_results, position_id)
--     local res = nil
--
--     for test_id, result in pairs(test_results) do
--         -- TODO: test_id is prefixed with suite name,
--         -- we should parse results smarter
--         if vim.endswith(position_id, test_id) then
--             res = result
--             break
--         end
--     end
--     return res
-- end

function M.build_test_result(junit_test, position)
    local result = nil
    local error = {}

    if junit_test.error_message then
        local msg = vim.split(junit_test.error_message, "\n")
        table.remove(msg, 1) -- it's just the name of the test, starts with - or x

        local last_line = table.remove(msg, #msg - 1) -- can be used to get a line number
        local line_num = string.match(junit_test.error_message, junit_test.file_name .. ":(%d*)")
        if line_num then
            error.line = tonumber(line_num) - 1 -- minus 1 because Lua indexes are 1-based
        else
            -- since there's no line num, then let's add it back
            table.insert(msg, last_line)
        end

        local formatted_msg = table.concat(msg, "\n")
        error.message = formatted_msg
    elseif junit_test.error_stacktrace then
        local line_num = string.match(junit_test.error_stacktrace, junit_test.file_name .. ":(%d*)")
        if line_num then
            error.line = tonumber(line_num) - 1
        end

        error.message = junit_test.error_stacktrace
    end

    if not vim.tbl_isempty(error) then
        result = {
            test_id = position.id,
            status = TEST_FAILED,
            errors = { error },
        }
    else
        result = {
            test_id = position.id,
            status = TEST_PASSED,
        }
    end

    return result
end

---@return neotest-scala.Framework
return M
