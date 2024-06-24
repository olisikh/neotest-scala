local M = {}

TEST_PASSED = "passed" -- the test passed
TEST_FAILED = "failed" -- the test failed

---@class neotest-scala.Framework
---@field build_command fun(runner: string, project: string, tree: neotest.Tree, name: string, extra_args: table|string): string[]
---@field get_test_results fun(output_lines: string[]): table<string, string>
---@field match_test nil|fun(junit_test: table<string, string>, position: neotest.Position): boolean
---@field build_test_result nil|fun(junit_test: table<string, string>, position: neotest.Position): table<string, any>

---Returns a framework class.
---@param framework string
---@return neotest-scala.Framework|nil
function M.get_framework_class(framework)
    if framework == "utest" then
        return require("neotest-scala.framework.utest")
    elseif framework == "munit" then
        return require("neotest-scala.framework.munit")
    elseif framework == "scalatest" then
        return require("neotest-scala.framework.scalatest")
    elseif framework == "specs2" then
        return require("neotest-scala.framework.specs2")
    elseif framework == "zio-test" then
        return require("neotest-scala.framework.zio-test")
    end
end

return M
