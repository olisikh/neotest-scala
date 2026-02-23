local ts = vim.treesitter
local lib = require("neotest.lib")
local utils = require("neotest-scala.utils")

local M = {}

---@class neotest-scala.JUnitTest
---@field name string
---@field namespace string
---@field error_message? string
---@field error_stacktrace? string
---@field error_type? string

---@class neotest-scala.JunitNamespace
---@field report_path string
---@field namespace string

--query
local query = [[
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
        (Name) @_4 (#any-of? @_4 "failure" "error")
        (Attribute 
          (Name) @_5 (#eq? @_5 "message")
          (AttValue) @testcase.message
        )?
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

local junit_query = ts.query.parse("xml", query)

---@param ns neotest-scala.JunitNamespace
---@return neotest-scala.JUnitTest[]
M.collect_results = function(ns)
    local results = {}

    local success, junit_xml = pcall(lib.files.read, ns.report_path)
    if not success then
        return {}
    end

    local report_tree = ts.get_string_parser(junit_xml, "xml")
    local parsed = report_tree:parse()[1]

    local query_results = junit_query:iter_matches(parsed:root(), report_tree:source())

    for _, matches, _ in query_results do
        local test_name_node = matches[3] and matches[3][1]
        local error_message_node = matches[6] and matches[6][1]
        local error_type_node = matches[8] and matches[8][1]
        local error_stacktrace_node = matches[9] and matches[9][1]

        local result = {}
        if test_name_node then
            result.name = utils.string_unescape_xml(
                utils.string_remove_dquotes(ts.get_node_text(test_name_node, report_tree:source()))
            )
        end
        if error_message_node then
            result.error_message = utils.string_unescape_xml(
                utils.string_remove_ansi(
                    utils.string_remove_dquotes(ts.get_node_text(error_message_node, report_tree:source()))
                )
            )
        end
        if error_type_node then
            result.error_type = utils.string_remove_dquotes(ts.get_node_text(error_type_node, report_tree:source()))
        end
        if error_stacktrace_node then
            result.error_stacktrace = utils.string_unescape_xml(
                utils.string_remove_ansi(
                    utils.string_remove_dquotes(ts.get_node_text(error_stacktrace_node, report_tree:source()))
                )
            )
        end

        result.namespace = ns.namespace

        table.insert(results, result)
    end

    return results
end

return M
