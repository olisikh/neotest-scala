local utils = require("neotest-scala.utils")

return function()
    ---Get test ID from the test line output.
    ---@param output string
    ---@return string
    local function get_test_id(output)
        local words = vim.split(output, " ", { trimempty = true })
        -- Strip the test success/failure indicator
        table.remove(words, 1)
        return table.concat(words, " ")
    end

    -- Get test results from the test output.
    ---@param output_lines string[]
    ---@return table<string, string>
    local function get_test_results(output_lines)
        local test_results = {}
        for _, line in ipairs(output_lines) do
            line = vim.trim(utils.strip_sbt_log_prefix(utils.strip_ainsi_chars(line)))

            if vim.startswith(line, "+") then
                local test_id = get_test_id(line)
                test_results[test_id] = TEST_PASSED
            else
                -- find an error line and strip to only the test name
                -- bloop adds [E] prefix
                local test_id = line:match("%[E%]%s+x (.*)$") or line:match("x (.*)$")
                if test_id ~= nil then
                    test_results[test_id] = TEST_FAILED
                end
            end
        end

        return test_results
    end

    local function build_test_namespace(tree, name)
        local parent_tree = tree:parent()
        local type = tree:data().type

        if parent_tree and parent_tree:data().type == "namespace" then
            local package = utils.get_package_name(parent_tree:data().path)
            local parent_name = parent_tree:data().name
            return package .. parent_name
        elseif parent_tree and parent_tree:data().type == "test" then
            return nil
        elseif type == "namespace" then
            local package = utils.get_package_name(tree:data().path)
            if not package then
                return nil
            end
            return package .. name
        elseif type == "file" then
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
        elseif type == "dir" then
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
        local test_namespace = build_test_namespace(tree, name)

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
            command = vim.tbl_flatten({ "bloop", "test", "--no-color", extra_args, project, full_test_path })
        elseif not test_namespace then
            -- TODO: can we resolve a class instead of running all tests in the project
            command = vim.tbl_flatten({ "sbt", extra_args, project .. "/test" })
        else
            -- TODO: Run sbt with colors, but figure out which ANSI sequence needs to be matched.
            local test_path = ""
            if tree:data().type == "test" then
                test_path = ' -- -z "' .. name .. '"'
            end

            command = vim.tbl_flatten({
                "sbt",
                "--no-colors",
                extra_args,
                project .. "/testOnly " .. test_namespace .. test_path,
            })
        end

        return command
    end

    -- Get test results from the test output.
    ---@param test_results table<string, string>
    ---@param position_id string
    ---@return string|nil
    local function match_func(test_results, position_id)
        local res = nil
        for test_id, result in pairs(test_results) do
            if position_id:match(test_id) then
                res = result
                break
            end
        end

        return res
    end

    return {
        get_test_results = get_test_results,
        build_command = build_command,
        match_func = match_func,
    }
end
