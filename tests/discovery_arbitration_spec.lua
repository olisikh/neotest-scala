local H = require("tests.helpers")

describe("framework arbitration", function()
  before_each(function()
    H.restore_mocks()
  end)

  after_each(function()
    H.restore_mocks()
  end)

  local function mk_tree(test_name)
    local namespace_data = { type = "namespace", name = "Suite" }
    local test_data = { type = "test", name = test_name }

    local namespace_node = {
      data = function()
        return namespace_data
      end,
    }

    local test_node = {
      data = function()
        return test_data
      end,
    }

    local tree = {
      iter_nodes = function()
        local nodes = { namespace_node, test_node }
        local i = 0
        return function()
          i = i + 1
          if i <= #nodes then
            return i, nodes[i]
          end
        end
      end,
    }

    return tree, namespace_data, test_data
  end

  it("picks one best framework for a file and annotates discovered positions", function()
    local adapter = require("neotest-scala")

    local scalatest_tree = mk_tree("" .. '"scalatest test"')
    local munit_tree, munit_namespace_data, munit_test_data = mk_tree("" .. '"munit test"')

    H.mock_fn("neotest-scala", "root", function()
      return "/tmp/project"
    end)

    H.mock_fn("neotest.lib", "files", {
      read = function()
        return [[
          import munit.FunSuite

          class ExampleSpec extends FunSuite {
            test("works") {
              assertEquals(1, 1)
            }
          }
        ]]
      end,
    })

    H.mock_fn("neotest-scala.metals", "get_frameworks", function()
      return { "scalatest", "munit" }
    end)

    H.mock_fn("neotest-scala.framework", "get_framework_class", function(name)
      if name == "scalatest" then
        return {
          discover_positions = function()
            return scalatest_tree
          end,
        }
      end

      if name == "munit" then
        return {
          discover_positions = function()
            return munit_tree
          end,
        }
      end

      return nil
    end)

    adapter({ cache_build_info = false })

    local tree = adapter.discover_positions("/tmp/project/src/test/scala/ExampleSpec.scala")

    assert.are.equal(munit_tree, tree)
    assert.are.equal("munit", munit_namespace_data.extra.framework)
    assert.are.equal("munit", munit_test_data.extra.framework)
  end)

  it("build_spec prefers framework pinned on discovered position", function()
    local adapter = require("neotest-scala")

    local selected_framework

    H.mock_fn("neotest-scala", "root", function()
      return "/tmp/project"
    end)

    H.mock_fn("neotest-scala.metals", "get_build_target_info", function()
      return {
        ["Target"] = { "munit-test" },
        ["Base Directory"] = { "file:/tmp/project/" },
      }
    end)

    H.mock_fn("neotest-scala.metals", "get_project_name", function()
      return "munit"
    end)

    H.mock_fn("neotest-scala.metals", "get_framework", function()
      return "scalatest"
    end)

    H.mock_fn("neotest-scala.build", "get_tool", function()
      return "sbt"
    end)

    H.mock_fn("neotest-scala.framework", "get_framework_class", function(name)
      selected_framework = name
      return {
        build_command = function()
          return { "echo", "ok" }
        end,
      }
    end)

    H.mock_fn("neotest-scala.strategy", "get_config", function()
      return { strategy = "integrated" }
    end)

    adapter({ cache_build_info = false })

    local spec = adapter.build_spec({
      tree = {
        data = function()
          return {
            type = "test",
            path = "/tmp/project/src/test/scala/ExampleSpec.scala",
            name = '"works"',
            extra = {
              framework = "munit",
            },
          }
        end,
      },
      extra_args = {},
    })

    assert.are.equal("munit", selected_framework)
    assert.are.equal("munit", spec.env.framework)
  end)
end)
