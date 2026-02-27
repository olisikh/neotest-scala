local H = require("tests.helpers")

local function mk_tree(test_ids)
  local nodes = {}
  for _, id in ipairs(test_ids) do
    table.insert(nodes, {
      data = function()
        return {
          type = "test",
          id = id,
          path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
        }
      end,
    })
  end

  return {
    iter_nodes = function()
      return ipairs(nodes)
    end,
  }
end

describe("results collect", function()
  before_each(function()
    H.restore_mocks()
  end)

  after_each(function()
    H.restore_mocks()
  end)

  it("hard-fails dap runs when no test suites were run", function()
    local results = require("neotest-scala.results")
    local tree = mk_tree({
      "com.example.MySpec.test one",
      "com.example.MySpec.test two",
    })

    H.mock_fn("neotest.lib", "files", {
      read = function()
        return [[
The test execution was successfully closed.
================================================================================
Total duration: 0ms
No test suites were run.
================================================================================
]]
      end,
    })

    H.mock_fn("neotest-scala.framework", "get_framework_class", function()
      return {
        parse_stdout_results = function()
          return {}
        end,
      }
    end)

    local collected = results.collect({
      strategy = {
        type = "scala",
        request = "launch",
      },
      env = {
        framework = "munit",
      },
    }, { output = "/tmp/out.log" }, tree)

    assert.are.equal(TEST_FAILED, collected["com.example.MySpec.test one"].status)
    assert.are.equal(TEST_FAILED, collected["com.example.MySpec.test two"].status)
    assert.are.equal("No test suites were run.", collected["com.example.MySpec.test one"].errors[1].message)
  end)

  it("returns parsed stdout results for dap runs when parser resolves tests", function()
    local results = require("neotest-scala.results")
    local tree = mk_tree({ "com.example.MySpec.test one" })
    local expected = {
      ["com.example.MySpec.test one"] = {
        status = TEST_FAILED,
        errors = { { message = "boom" } },
      },
    }

    H.mock_fn("neotest.lib", "files", {
      read = function()
        return "test output"
      end,
    })

    H.mock_fn("neotest-scala.framework", "get_framework_class", function()
      return {
        parse_stdout_results = function()
          return expected
        end,
      }
    end)

    local collected = results.collect({
      strategy = {
        type = "scala",
        request = "launch",
      },
      env = {
        framework = "munit",
      },
    }, { output = "/tmp/out.log" }, tree)

    assert.are.same(expected, collected)
  end)

  it("keeps non-dap bloop behavior unchanged", function()
    local results = require("neotest-scala.results")
    local tree = mk_tree({ "com.example.MySpec.test one" })
    local parse_called = false

    H.mock_fn("neotest.lib", "files", {
      read = function()
        return "test output"
      end,
    })

    H.mock_fn("neotest-scala.framework", "get_framework_class", function()
      return {
        parse_stdout_results = function()
          parse_called = true
          return {
            ["com.example.MySpec.test one"] = {
              status = TEST_PASSED,
            },
          }
        end,
      }
    end)

    local collected = results.collect({
      env = {
        framework = "munit",
        build_tool = "bloop",
      },
    }, { output = "/tmp/out.log" }, tree)

    assert.is_true(parse_called)
    assert.are.equal(TEST_PASSED, collected["com.example.MySpec.test one"].status)
  end)
end)
