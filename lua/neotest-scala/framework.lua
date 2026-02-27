local M = {}

M.TEST_PASSED = "passed"
M.TEST_FAILED = "failed"

_G.TEST_PASSED = M.TEST_PASSED
_G.TEST_FAILED = M.TEST_FAILED

local FRAMEWORK_MARKERS = {
    scalatest = {
        "org%.scalatest",
        "extends%s+AnyFunSuite",
        "extends%s+AsyncFunSuite",
        "extends%s+FixtureAnyFunSuite",
        "extends%s+AnyFreeSpec",
        "extends%s+AsyncFreeSpec",
        "extends%s+FixtureAnyFreeSpec",
        "extends%s+AnyFlatSpec",
        "extends%s+AsyncFlatSpec",
        "extends%s+FixtureAnyFlatSpec",
        "extends%s+AnyPropSpec",
        "extends%s+FixtureAnyPropSpec",
    },
    munit = {
        "org%.scalameta%.munit",
        "munit%.FunSuite",
        "extends%s+FunSuite",
        "extends%s+CatsEffectSuite",
        "extends%s+ScalaCheckSuite",
        "extends%s+DisciplineSuite",
        "extends%s+ZSuite",
        "extends%s+ZIOSuite",
    },
    specs2 = {
        "org%.specs2",
        "extends%s+Specification",
        's2"""',
    },
    utest = {
        "import%s+utest",
        "extends%s+TestSuite",
        "utest%.Tests",
    },
    ["zio-test"] = {
        "zio%.test",
        "extends%s+ZIOSpecDefault",
        "ZIOSpecDefault",
    },
}

---@class neotest-scala.PositionExtra
---@field textspec_path? string
---@field framework? string

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

---@param tree neotest.Tree
---@return integer, integer
local function count_discovered_positions(tree)
    local test_count = 0
    local namespace_count = 0

    if not tree or type(tree.iter_nodes) ~= "function" then
        return test_count, namespace_count
    end

    for _, node in tree:iter_nodes() do
        local data = node:data()
        if data.type == "test" then
            test_count = test_count + 1
        elseif data.type == "namespace" then
            namespace_count = namespace_count + 1
        end
    end

    return test_count, namespace_count
end

---@param content string
---@param framework_name string
---@return integer
local function marker_score(content, framework_name)
    local markers = FRAMEWORK_MARKERS[framework_name]
    if not markers then
        return 0
    end

    local score = 0
    for _, pattern in ipairs(markers) do
        if content:match(pattern) then
            score = score + 1
        end
    end

    return score
end

---@param tree neotest.Tree
---@param framework_name string
function M.annotate_tree_framework(tree, framework_name)
    if not tree or type(tree.iter_nodes) ~= "function" then
        return
    end

    for _, node in tree:iter_nodes() do
        local data = node:data()
        data.extra = data.extra or {}
        data.extra.framework = framework_name
    end
end

---@param opts { frameworks: string[], path: string, content: string }
---@return neotest.Tree|nil, string|nil
function M.select_framework_tree(opts)
    local frameworks = opts.frameworks or {}
    local path = opts.path
    local content = opts.content

    local best_tree = nil
    local best_framework = nil
    local best_score = nil
    local best_test_count = -1
    local best_namespace_count = -1

    for _, fw_name in ipairs(frameworks) do
        local framework = M.get_framework_class(fw_name)
        if framework then
            local tree = framework.discover_positions({
                path = path,
                content = content,
            })

            if tree then
                local test_count, namespace_count = count_discovered_positions(tree)
                if test_count > 0 then
                    local score = test_count * 10 + namespace_count * 3 + marker_score(content, fw_name) * 20

                    local is_better = best_score == nil
                        or score > best_score
                        or (score == best_score and test_count > best_test_count)
                        or (
                            score == best_score
                            and test_count == best_test_count
                            and namespace_count > best_namespace_count
                        )

                    if is_better then
                        best_score = score
                        best_test_count = test_count
                        best_namespace_count = namespace_count
                        best_framework = fw_name
                        best_tree = tree
                    end
                end
            end
        end
    end

    if best_tree and best_framework then
        M.annotate_tree_framework(best_tree, best_framework)
    end

    return best_tree, best_framework
end

return M
