local M = {}

M.TEST_PASSED = "passed"
M.TEST_FAILED = "failed"

_G.TEST_PASSED = M.TEST_PASSED
_G.TEST_FAILED = M.TEST_FAILED

---@class neotest-scala.Framework
---@field name string
---@field build_command fun(root_path: string, project: string, tree: neotest.Tree, name: string, extra_args: table|string): string[]
---@field match_test nil|fun(junit_test: table<string, string>, position: neotest.Position): boolean
---@field build_test_result nil|fun(junit_test: table<string, string>, position: neotest.Position): table<string, any>
---@field build_namespace nil|fun(ns_node: neotest.Tree, report_prefix: string, node: neotest.Tree): table
---@field discover_positions nil|fun(style: string, path: string, content: string, opts: table): neotest.Tree
---@field detect_style nil|fun(content: string): string|nil
---@field parse_stdout_results nil|fun(output: string, tree: neotest.Tree): table<string, neotest.Result>

---@param framework string
---@return neotest-scala.Framework|nil
function M.get_framework_class(framework)
    local prefix = "neotest-scala.framework."

    if framework == "utest" then
        return require(prefix .. "utest")
    elseif framework == "munit" then
        return require(prefix .. "munit")
    elseif framework == "scalatest" then
        return require(prefix .. "scalatest")
    elseif framework == "specs2" then
        return require(prefix .. "specs2")
    elseif framework == "zio-test" then
        return require(prefix .. "zio-test")
    end

    return nil
end

return M
