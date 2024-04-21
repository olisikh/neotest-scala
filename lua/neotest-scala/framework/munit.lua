local utils = require("neotest-scala.utils")

---@return neotest-scala.Framework
return function()
    -- Builds a test path from the current position in the tree.
    ---@param tree neotest.Tree
    ---@param name string
    ---@return string|nil
    local function build_test_path(tree, name)
        local parent_tree = tree:parent()
        local type = tree:data().type
        if parent_tree and parent_tree:data().type == "namespace" then
            local package = utils.get_package_name(parent_tree:data().path)
            local parent_name = parent_tree:data().name
            return package .. parent_name .. "." .. name
        end
        if parent_tree and parent_tree:data().type == "test" then
            local parent_pos = parent_tree:data()
            return build_test_path(parent_tree, utils.get_position_name(parent_pos)) .. "." .. name
        end
        if type == "namespace" then
            local package = utils.get_package_name(tree:data().path)
            if not package then
                return nil
            end
            return package .. name .. ".*"
        end
        if type == "file" then
            local test_suites = {}
            for _, child in tree:iter_nodes() do
                if child:data().type == "namespace" then
                    table.insert(test_suites, child:data().name)
                end
            end
            if test_suites then
                local package = utils.get_package_name(tree:data().path)
                return package .. "*"
            end
        end
        if type == "dir" then
            return "*"
        end
        return nil
    end

    --- Builds a command for running tests for the framework.
    ---@param runner string
    ---@param project string
    ---@param tree neotest.Tree
    ---@param name string
    ---@param extra_args table|string
    ---@return string[]
    local function build_command(runner, project, tree, name, extra_args)
        local test_path = build_test_path(tree, name)
        return utils.build_command_with_test_path(project, runner, test_path, extra_args)
    end

    ---Get test ID from the test line output.
    ---@param output string
    ---@return string
    local function get_test_name(output, prefix)
        return output:match("^" .. prefix .. " (.*) %d*%.?%d+s.*") or nil
    end

    ---Get test namespace from the test line output.
    ---@param output string
    ---@return string|nil
    local function get_test_namespace(output)
        return output:match("^([%w%.]+):") or nil
    end

    -- Get test results from the test output.
    ---@param output_lines string[]
    ---@return table<string, string>
    local function get_test_results(output_lines)
        local test_results = {}
        local test_namespace = nil
        for _, line in ipairs(output_lines) do
            line = vim.trim(utils.strip_ainsi_chars(line))
            local current_namespace = get_test_namespace(line)
            if current_namespace and (not test_namespace or test_namespace ~= current_namespace) then
                test_namespace = current_namespace
            end
            if test_namespace and vim.startswith(line, "+") then
                local test_name = get_test_name(line, "+")
                if test_name then
                    local test_id = test_namespace .. "." .. vim.trim(test_name)
                    test_results[test_id] = TEST_PASSED
                end
            elseif test_namespace and vim.startswith(line, "==> X") then
                local test_name = get_test_name(line, "==> X")
                if test_name then
                    test_results[vim.trim(test_name)] = TEST_FAILED
                end
            end
        end
        return test_results
    end

    return {
        get_test_results = get_test_results,
        build_command = build_command,
    }
end
