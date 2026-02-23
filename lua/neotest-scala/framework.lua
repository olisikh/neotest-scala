local M = {}

M.TEST_PASSED = "passed"
M.TEST_FAILED = "failed"

_G.TEST_PASSED = M.TEST_PASSED
_G.TEST_FAILED = M.TEST_FAILED

---@class neotest-scala.PositionExtra
---@field textspec_path? string

---@class neotest-scala.PositionWithExtra: neotest.Position
---@field extra? neotest-scala.PositionExtra

---@class neotest-scala.Framework
---@field name string
---@field build_command fun(opts: { root_path: string, project: string, tree: neotest.Tree, name: string|nil, extra_args: nil|string|string[], build_tool: "bloop"|"sbt"|nil }): string[]
---@field build_position_result fun( opts: { position: neotest.Position|neotest-scala.PositionWithExtra, test_node: neotest.Tree, junit_results: neotest-scala.JUnitTest[], namespace: table }): neotest.Result|nil
---@field build_namespace fun(ns_node: neotest.Tree, report_prefix: string, node: neotest.Tree): table
---@field discover_positions fun(opts: { path: string, content: string }): neotest.Tree|nil
---@field parse_stdout_results fun(output: string, tree: neotest.Tree): table<string, neotest.Result>

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
