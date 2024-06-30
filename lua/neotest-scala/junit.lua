local ts = vim.treesitter
local lib = require("neotest.lib")
local utils = require("neotest-scala.utils")

local M = {}

--query
local junit_query = ts.query.parse(
    "xml",
    [[
(element 
  (STag 
    (Name) @_1 (#eq? @_1 "testcase")
    (Attribute 
      (Name) @_2 (#eq? @_2 "name")
      (AttValue) @testcase.name
    )
  )
  (content
    (element
      (STag 
        (Name) @_4 (#eq? @_4 "failure")
        (Attribute 
          (Name) @_5 (#eq? @_5 "message")
          (AttValue) @testcase.message
        )
        (Attribute
          (Name) @_7 (#eq? @_7 "type")
          (AttValue) @testcase.error_type
        )
      )
      (content) @testcase.error_message
    )? @testcase.content
  ) @testcase
)
]]
)

M.collect_results = function(namespace)
    local junit_tests = {}

    local success, junit_xml = pcall(lib.files.read, namespace.report_file_name)
    if not success then
        return {}
    end

    local report_tree = ts.get_string_parser(junit_xml, "xml")
    local parsed = report_tree:parse()[1]

    local query_results = junit_query:iter_matches(parsed:root(), report_tree:source())

    for _, matches, _ in query_results do
        local test_name_node = matches[3]
        local error_message_node = matches[6]
        local error_type_node = matches[8]
        local error_stacktrace_node = matches[9]

        local test = {}
        if test_name_node then
            test.name = utils.string_unescape_xml(
                utils.string_remove_dquotes(ts.get_node_text(test_name_node, report_tree:source()))
            )
        end
        if error_message_node then
            test.error_message = utils.string_unescape_xml(
                utils.string_remove_ansi(
                    utils.string_remove_dquotes(ts.get_node_text(error_message_node, report_tree:source()))
                )
            )
        end
        if error_type_node then
            test.error_type = utils.string_remove_dquotes(ts.get_node_text(error_type_node, report_tree:source()))
        end
        if error_stacktrace_node then
            test.error_stacktrace = utils.string_unescape_xml(
                utils.string_remove_ansi(
                    utils.string_remove_dquotes(ts.get_node_text(error_stacktrace_node, report_tree:source()))
                )
            )
        end

        test.file_name = namespace.file_name
        test.namespace_name = namespace.namespace_name

        table.insert(junit_tests, test)
    end

    return junit_tests
end

return M
