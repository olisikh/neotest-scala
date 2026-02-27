package.loaded["neotest.lib"] = package.loaded["neotest.lib"] or {
  files = {
    read_lines = function(_)
      return { "package com.example" }
    end,
  },
}
package.loaded["neotest.lib"].treesitter = package.loaded["neotest.lib"].treesitter or {}

local parse_positions_calls = {}
package.loaded["neotest.lib"].treesitter.parse_positions = function(path, query, opts)
  table.insert(parse_positions_calls, { path = path, query = query, opts = opts })
  return { path = path, query = query, opts = opts }
end

local scalatest = require("neotest-scala.framework.scalatest")
local H = require("tests.helpers")

describe("scalatest", function()
  describe("discover_positions", function()
    before_each(function()
      parse_positions_calls = {}
    end)

    it("discovers tests for AnyFunSuite", function()
      local tree = scalatest.discover_positions({
        path = "/project/src/test/scala/com/example/FunSuiteSpec.scala",
        content = [[
          import org.scalatest.funsuite.AnyFunSuite

          class FunSuiteSpec extends AnyFunSuite {
            test("works") {}
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.are.equal(1, #parse_positions_calls)
      assert.is_true(parse_positions_calls[1].query:find('"test"', 1, true) ~= nil)
    end)

    it("supports interpolated test names for AnyFunSuite", function()
      local tree = scalatest.discover_positions({
        path = "/project/src/test/scala/com/example/FunSuiteSpec.scala",
        content = [[
          import org.scalatest.funsuite.AnyFunSuite

          class FunSuiteSpec extends AnyFunSuite {
            val baseName = "suite"
            test(s"$baseName works") {}
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.are.equal(1, #parse_positions_calls)
      assert.is_true(parse_positions_calls[1].query:find("interpolated_string_expression", 1, true) ~= nil)
    end)

    it("discovers tests for AsyncFlatSpec", function()
      local tree = scalatest.discover_positions({
        path = "/project/src/test/scala/com/example/AsyncFlatSpec.scala",
        content = [[
          import org.scalatest.flatspec.AsyncFlatSpec

          class AsyncFlatSpec extends AsyncFlatSpec {
            "a service" should "work" in {}
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.are.equal(1, #parse_positions_calls)
      assert.is_true(parse_positions_calls[1].query:find('"should"', 1, true) ~= nil)
    end)

    it("discovers tests for FixtureAnyFunSuite", function()
      local tree = scalatest.discover_positions({
        path = "/project/src/test/scala/com/example/FixtureFunSuite.scala",
        content = [[
          import org.scalatest.funsuite.FixtureAnyFunSuite

          class FixtureFunSuite extends FixtureAnyFunSuite {
            type FixtureParam = String
            test("works") { _ => () }
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.are.equal(1, #parse_positions_calls)
      assert.is_true(parse_positions_calls[1].query:find('"test"', 1, true) ~= nil)
    end)

    it("discovers tests for AnyPropSpec", function()
      local tree = scalatest.discover_positions({
        path = "/project/src/test/scala/com/example/PropSpec.scala",
        content = [[
          import org.scalatest.propspec.AnyPropSpec

          class PropSpec extends AnyPropSpec {
            property("works") {}
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.are.equal(1, #parse_positions_calls)
      assert.is_true(parse_positions_calls[1].query:find('"property"', 1, true) ~= nil)
    end)

    it("discovers tests for AsyncWordSpec", function()
      local tree = scalatest.discover_positions({
        path = "/project/src/test/scala/com/example/AsyncWordSpecSuite.scala",
        content = [[
          import org.scalatest.wordspec.AsyncWordSpec

          class AsyncWordSpecSuite extends AsyncWordSpec {
            "service" should {
              "work" in {}
            }
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.are.equal(1, #parse_positions_calls)
      assert.is_true(parse_positions_calls[1].query:find('"in"', 1, true) ~= nil)
    end)

    it("discovers tests for AnyFunSpec", function()
      local tree = scalatest.discover_positions({
        path = "/project/src/test/scala/com/example/FunSpec.scala",
        content = [[
          import org.scalatest.funspec.AnyFunSpec

          class FunSpec extends AnyFunSpec {
            describe("List operations") {
              it("works") {}
            }
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.are.equal(1, #parse_positions_calls)
      assert.is_true(parse_positions_calls[1].query:find('"describe"', 1, true) ~= nil)
      assert.is_true(parse_positions_calls[1].query:find('"it"', 1, true) ~= nil)
    end)

    it("discovers tests for AnyFeatureSpec", function()
      local tree = scalatest.discover_positions({
        path = "/project/src/test/scala/com/example/FeatureSpec.scala",
        content = [[
          import org.scalatest.featurespec.AnyFeatureSpec

          class FeatureSpec extends AnyFeatureSpec {
            Feature("Authentication") {
              Scenario("successful login") {}
            }
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.are.equal(1, #parse_positions_calls)
      assert.is_true(parse_positions_calls[1].query:find('"Feature"', 1, true) ~= nil)
      assert.is_true(parse_positions_calls[1].query:find('"Scenario"', 1, true) ~= nil)
    end)

    it("discovers tests for RefSpec", function()
      local tree = scalatest.discover_positions({
        path = "/project/src/test/scala/com/example/RefSpecSuite.scala",
        content = [[
          import org.scalatest.refspec.RefSpec

          class RefSpecSuite extends RefSpec {
            def `successful example`(): Unit = {}
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.are.equal(1, #parse_positions_calls)
      assert.is_true(parse_positions_calls[1].query:find("function_definition", 1, true) ~= nil)
    end)

    it("returns nil for unsupported style", function()
      local tree = scalatest.discover_positions({
        path = "/project/src/test/scala/com/example/Nope.scala",
        content = [[
          import munit.FunSuite

          class Nope extends FunSuite {
            test("nope") {}
          }
        ]],
      })

      assert.is_nil(tree)
      assert.are.equal(0, #parse_positions_calls)
    end)
  end)

  describe("build_command", function()
    after_each(function()
      H.restore_mocks()
    end)

    it("delegates to build.command with all arguments", function()
      local called_with = nil
      H.mock_fn("neotest-scala.build", "command", function(opts)
        called_with = opts
        return { "mocked", "command" }
      end)

      local root_path = "/project/root"
      local project = "myproject"
      local tree = { data = { type = "test" } }
      local name = "MyTestClass"
      local extra_args = { "--verbose" }

      local result = scalatest.build_command({
        root_path = root_path,
        project = project,
        tree = tree,
        name = name,
        extra_args = extra_args,
      })

      assert(called_with, "build_command should have been called")
      assert.are.equal(root_path, called_with.root_path)
      assert.are.equal(project, called_with.project)
      assert.are.same(tree, called_with.tree)
      assert.are.equal(name, called_with.name)
      assert.are.same(extra_args, called_with.extra_args)
      assert.are.same({ "mocked", "command" }, result)
    end)

    it("returns the result from utils.build_command unchanged", function()
      local expected_command = { "sbt", "myproject/testOnly", "com.example.TestSpec" }
      H.mock_fn("neotest-scala.build", "command", function()
        return expected_command
      end)

      local result = scalatest.build_command({
        root_path = "/root",
        project = "myproject",
        tree = {},
        name = "TestSpec",
        extra_args = {},
      })

      assert.are.same(expected_command, result)
    end)

    it("handles nil extra_args", function()
      local called_with = nil
      H.mock_fn("neotest-scala.build", "command", function(opts)
        called_with = opts
        return {}
      end)

      scalatest.build_command({
        root_path = "/root",
        project = "project",
        tree = {},
        name = "Test",
        extra_args = nil,
      })

      assert(called_with, "build_command should have been called")
      assert.is_nil(called_with.extra_args)
    end)

    it("builds full test path for FreeSpec-style tests with parent contexts", function()
      local called_with = nil
      H.mock_fn("neotest-scala.build", "command", function(opts)
        called_with = opts
        return {}
      end)

      -- Mock tree structure: "Hello, ScalaTest!" test inside "FreeSpec" context
      local parent_data = { type = "test", name = '"FreeSpec"' }
      local parent_mock = {
        data = function() return parent_data end,
        parent = function() return nil end,
      }
      local tree_data = { type = "test", name = '"Hello, ScalaTest!"' }
      local tree_mock = {
        data = function() return tree_data end,
        parent = function() return parent_mock end,
      }

      scalatest.build_command({
        root_path = "/root",
        project = "project",
        tree = tree_mock,
        name = "Hello, ScalaTest!",
        extra_args = {},
      })

      assert(called_with, "build_command should have been called")
      assert.are.equal("FreeSpec Hello, ScalaTest!", called_with.name)
    end)

    it("builds nested test path for deeply nested FreeSpec tests", function()
      local called_with = nil
      H.mock_fn("neotest-scala.build", "command", function(opts)
        called_with = opts
        return {}
      end)

      -- Mock tree structure: "nested" test inside "deeply" context inside "FreeSpec" context
      local grandparent_data = { type = "test", name = '"FreeSpec"' }
      local grandparent_mock = {
        data = function() return grandparent_data end,
        parent = function() return nil end,
      }
      local parent_data = { type = "test", name = '"deeply"' }
      local parent_mock = {
        data = function() return parent_data end,
        parent = function() return grandparent_mock end,
      }
      local tree_data = { type = "test", name = '"nested"' }
      local tree_mock = {
        data = function() return tree_data end,
        parent = function() return parent_mock end,
      }

      scalatest.build_command({
        root_path = "/root",
        project = "project",
        tree = tree_mock,
        name = "nested",
        extra_args = {},
      })

      assert(called_with, "build_command should have been called")
      assert.are.equal("FreeSpec deeply nested", called_with.name)
    end)

    it("passes name unchanged for non-test types", function()
      local called_with = nil
      H.mock_fn("neotest-scala.build", "command", function(opts)
        called_with = opts
        return {}
      end)

      local tree_data = { type = "namespace", name = "MySpec" }
      local tree_mock = {
        data = function() return tree_data end,
      }

      scalatest.build_command({
        root_path = "/root",
        project = "project",
        tree = tree_mock,
        name = "MySpec",
        extra_args = {},
      })

      assert(called_with, "build_command should have been called")
      assert.are.equal("MySpec", called_with.name)
    end)
  end)

  describe("build_test_result matching", function()
    before_each(function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function(_)
        return "com.example."
      end)
    end)

    after_each(function()
      H.restore_mocks()
    end)

    it("removes spaces from test names for matching", function()
      local junit_test = {
        name = "should do something cool",
        namespace = "MySpec",
      }

      local position = {
        path = "/path/to/MySpec.scala",
        id = "com.example.MySpec.shoulddosomethingcool",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
    end)

    it("handles exact matches correctly", function()
      local junit_test = {
        name = "testMethod",
        namespace = "CalculatorSpec",
      }

      local position = {
        path = "/path/to/CalculatorSpec.scala",
        id = "com.example.CalculatorSpec.testMethod",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
    end)

    it("returns false for non-matching test names", function()
      local junit_test = {
        name = "testAddition",
        namespace = "CalculatorSpec",
      }

      local position = {
        path = "/path/to/CalculatorSpec.scala",
        id = "com.example.CalculatorSpec.testSubtraction",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_nil(result)
    end)

    it("handles test names with multiple spaces", function()
      local junit_test = {
        name = "should return true when input is valid",
        namespace = "ValidatorSpec",
      }

      local position = {
        path = "/path/to/ValidatorSpec.scala",
        id = "com.example.ValidatorSpec.shouldreturntruewheninputisvalid",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
    end)

    it("handles test names without spaces", function()
      local junit_test = {
        name = "simpleTestName",
        namespace = "SimpleSpec",
      }

      local position = {
        path = "/path/to/SimpleSpec.scala",
        id = "com.example.SimpleSpec.simpleTestName",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
    end)

    it("handles different namespaces", function()
      local junit_test = {
        name = "myTest",
        namespace = "DifferentSpec",
      }

      local position = {
        path = "/path/to/MySpec.scala",
        id = "com.example.MySpec.myTest",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_nil(result)
    end)

    it("handles empty package name", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function(_)
        return ""
      end)

      local junit_test = {
        name = "myTest",
        namespace = "MySpec",
      }

      local position = {
        path = "/path/to/MySpec.scala",
        id = "MySpec.myTest",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
    end)

    it("handles FreeSpec test names with parent context", function()
      local junit_test = {
        name = "HelloWorldSpec failing test",
        namespace = "MySpecSpec",
      }

      local position = {
        path = "/path/to/MySpecSpec.scala",
        id = "com.example.MySpecSpec.HelloWorldSpecfailingtest",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
    end)

    it("matches FreeSpec JUnit names with dots in position.id", function()
      -- JUnit name has parent context prepended: "FreeSpec Hello, ScalaTest!"
      -- position.id has dots between all parts: "com.example.FreeSpec.FreeSpec.Hello, ScalaTest!"
      local junit_test = {
        name = "FreeSpec Hello, ScalaTest!",
        namespace = "FreeSpec",
      }

      local position = {
        path = "/path/to/FreeSpec.scala",
        id = "com.example.FreeSpec.FreeSpec.Hello, ScalaTest!",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
    end)

    it("matches nested FreeSpec tests with multiple parent contexts", function()
      local junit_test = {
        name = "FreeSpec deeply nested",
        namespace = "FreeSpec",
      }

      local position = {
        path = "/path/to/FreeSpec.scala",
        id = "com.example.FreeSpec.FreeSpec.deeply.nested",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
    end)

    it("returns false for FreeSpec tests with different parent contexts", function()
      local junit_test = {
        name = "OtherContext Hello, ScalaTest!",
        namespace = "FreeSpec",
      }

      local position = {
        path = "/path/to/FreeSpec.scala",
        id = "com.example.FreeSpec.FreeSpec.Hello, ScalaTest!",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_nil(result)
    end)

    it("still matches regular tests without parent contexts", function()
      local junit_test = {
        name = "testMethod",
        namespace = "CalculatorSpec",
      }

      local position = {
        path = "/path/to/CalculatorSpec.scala",
        id = "com.example.CalculatorSpec.testMethod",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
    end)

    it("matches AnyFlatSpec JUnit names with behavior prefix", function()
      local junit_test = {
        name = "A Stack should fail",
        namespace = "FlatSpec",
        error_message = "1 did not equal 2",
      }

      local position = {
        path = "/path/to/FlatSpec.scala",
        id = "com.example.FlatSpec.fail",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
      assert.are.equal(TEST_FAILED, result.status)
    end)

    it("matches AnyFlatSpec JUnit names with XML-unescaped symbols", function()
      local junit_test = {
        name = "A Stack should pop values in last-in-first-out order",
        namespace = "FlatSpec",
      }

      local position = {
        path = "/path/to/FlatSpec.scala",
        id = "com.example.FlatSpec.pop values in last-in-first-out order",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
      assert.are.equal(TEST_PASSED, result.status)
    end)

    it("matches AnyWordSpec JUnit names with behavior prefix", function()
      local junit_test = {
        name = "A calculator should add numbers successfully",
        namespace = "WordSpec",
      }

      local position = {
        path = "/path/to/WordSpec.scala",
        id = "com.example.WordSpec.add numbers successfully",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
      assert.are.equal(TEST_PASSED, result.status)
    end)

    it("matches AnyFunSpec JUnit names with describe context", function()
      local junit_test = {
        name = "List operations supports successful checks",
        namespace = "FunSpec",
      }

      local position = {
        path = "/path/to/FunSpec.scala",
        id = "com.example.FunSpec.List operations.supports successful checks",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
      assert.are.equal(TEST_PASSED, result.status)
    end)

    it("matches AnyFeatureSpec JUnit names with Feature/Scenario prefixes", function()
      local junit_test = {
        name = "Feature: Authentication Scenario: successful login",
        namespace = "FeatureSpec",
      }

      local position = {
        path = "/path/to/FeatureSpec.scala",
        id = "com.example.FeatureSpec.Authentication.successful login",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
      assert.are.equal(TEST_PASSED, result.status)
    end)

    it("matches RefSpec names discovered with backticks", function()
      local junit_test = {
        name = "successful example",
        namespace = "RefSpecSuite",
      }

      local position = {
        path = "/path/to/RefSpecSuite.scala",
        id = "com.example.RefSpecSuite.successfulexample",
        name = "`successful example`",
        type = "test",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.is_not_nil(result)
      assert.are.equal(TEST_PASSED, result.status)
    end)
  end)

  describe("build_test_result", function()
    before_each(function()
      H.mock_fn("neotest-scala.utils", "get_file_name", function(path)
        return path:match("([^/]+)$")
      end)
    end)

    after_each(function()
      H.restore_mocks()
    end)

    it("extracts error message from error_message field", function()
      local junit_test = {
        error_message = "1 did not equal 2",
        error_stacktrace = "org.scalatest.exceptions.TestFailedException: 1 did not equal 2\n  at com.example.FunSuiteSpec.test(FunSuiteSpec.scala:12)",
      }
      local position = {
        path = "/project/src/test/scala/com/example/FunSuiteSpec.scala",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.are.equal(TEST_FAILED, result.status)
      assert.is_not_nil(result.errors)
      assert.are.equal(1, #result.errors)
      assert.are.equal("1 did not equal 2", result.errors[1].message)
    end)

    it("extracts line number from stacktrace", function()
      local junit_test = {
        error_message = "1 did not equal 2",
        error_stacktrace = "org.scalatest.exceptions.TestFailedException: 1 did not equal 2\n  at com.example.FunSuiteSpec.test(FunSuiteSpec.scala:12)",
      }
      local position = {
        path = "/project/src/test/scala/com/example/FunSuiteSpec.scala",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.are.equal(TEST_FAILED, result.status)
      assert.are.equal(11, result.errors[1].line)
    end)

    it("extracts the HIGHEST line number when multiple file references exist", function()
      local junit_test = {
        error_message = "1 did not equal 2",
        error_stacktrace = "org.scalatest.exceptions.TestFailedException: 1 did not equal 2\n  at org.scalatest.matchers.should.Matchers.shouldEqual(Matchers.scala:6893)\n  at com.example.FunSuiteSpec.shouldEqual(FunSuiteSpec.scala:7)\n  at com.example.FunSuiteSpec.testFun$proxy2$1(FunSuiteSpec.scala:12)\n  at com.example.FunSuiteSpec.$init$$$anonfun$2(FunSuiteSpec.scala:11)",
      }
      local position = {
        path = "/project/src/test/scala/com/example/FunSuiteSpec.scala",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.are.equal(TEST_FAILED, result.status)
      assert.are.equal(11, result.errors[1].line)
    end)

    it("extracts message from stacktrace when no error_message", function()
      local junit_test = {
        error_stacktrace = "java.lang.RuntimeException: kaboom\n  at com.example.FunSuiteSpec.test(FunSuiteSpec.scala:15)",
      }
      local position = {
        path = "/project/src/test/scala/com/example/FunSuiteSpec.scala",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.are.equal(TEST_FAILED, result.status)
      assert.are.equal("java.lang.RuntimeException: kaboom", result.errors[1].message)
    end)

    it("returns passed status when no error", function()
      local junit_test = {}
      local position = {
        path = "/project/src/test/scala/com/example/FunSuiteSpec.scala",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.are.equal(TEST_PASSED, result.status)
      assert.is_nil(result.errors)
    end)

    it("handles missing line number in stacktrace", function()
      local junit_test = {
        error_message = "Some error without line info",
        error_stacktrace = "org.scalatest.exceptions.TestFailedException: Some error",
      }
      local position = {
        path = "/project/src/test/scala/com/example/FunSuiteSpec.scala",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.are.equal(TEST_FAILED, result.status)
      assert.are.equal("Some error without line info", result.errors[1].message)
      assert.is_nil(result.errors[1].line)
    end)

    it("removes first-line (FileName.scala:line) suffix from error message", function()
      local junit_test = {
        error_message = "1 did not equal 2 (FunSuiteSpec.scala:12)",
        error_stacktrace = "org.scalatest.exceptions.TestFailedException: 1 did not equal 2\n  at com.example.FunSuiteSpec.test(FunSuiteSpec.scala:12)",
      }
      local position = {
        path = "/project/src/test/scala/com/example/FunSuiteSpec.scala",
      }

      local result = scalatest.build_test_result(junit_test, position)

      assert.are.equal(TEST_FAILED, result.status)
      assert.are.equal("1 did not equal 2", result.errors[1].message)
      assert.are.equal(11, result.errors[1].line)
    end)
  end)

  describe("parse_stdout_results", function()
    local function mk_tree(test_positions)
      local nodes = {}
      for _, pos in ipairs(test_positions) do
        table.insert(nodes, {
          data = function()
            return pos
          end,
        })
      end

      return {
        iter_nodes = function()
          local i = 0
          return function()
            i = i + 1
            if i <= #nodes then
              return i, nodes[i]
            end
          end
        end,
      }
    end

    it("parses FreeSpec bloop failures with nested output and line numbers", function()
      local tree = mk_tree({
        {
          type = "test",
          id = "com.example.FreeSpec.Hello, ScalaTest!.deeeeeeeeep.even deeeeeeeeeper.test",
          name = '"test"',
          path = "/project/src/test/scala/com/example/FreeSpec.scala",
        },
        {
          type = "test",
          id = "com.example.FreeSpec.failing test",
          name = '"failing test"',
          path = "/project/src/test/scala/com/example/FreeSpec.scala",
        },
        {
          type = "test",
          id = "com.example.FreeSpec.deeply.nested",
          name = '"nested"',
          path = "/project/src/test/scala/com/example/FreeSpec.scala",
        },
        {
          type = "test",
          id = "com.example.FreeSpec.failing",
          name = '"failing"',
          path = "/project/src/test/scala/com/example/FreeSpec.scala",
        },
        {
          type = "test",
          id = "com.example.FreeSpec.custom exception",
          name = '"custom exception"',
          path = "/project/src/test/scala/com/example/FreeSpec.scala",
        },
      })

      local output = [[
FreeSpec
- Hello, ScalaTest!
  deeeeeeeeep
    even deeeeeeeeeper
    - test *** FAILED ***
      1 did not equal 2 (FreeSpec.scala:17)
- failing test *** FAILED ***
  1 did not equal 2 (FreeSpec.scala:22)
  deeply
  - nested *** FAILED ***
    1 did not equal 5 (FreeSpec.scala:26)
- failing *** FAILED ***
  java.lang.RuntimeException: boom
  at com.example.FreeSpec.$init$$$anonfun$1$$anonfun$5(FreeSpec.scala:30)
  at org.scalatest.Transformer.apply$$anonfun$1(Transformer.scala:22)
  ...
- custom exception *** FAILED ***
  com.example.Babbah$:
  ...
Execution took 18ms
6 tests, 1 passed, 5 failed
]]

      local results = scalatest.parse_stdout_results(output, tree)

      assert.are.equal(TEST_FAILED, results["com.example.FreeSpec.Hello, ScalaTest!.deeeeeeeeep.even deeeeeeeeeper.test"].status)
      assert.are.equal(16, results["com.example.FreeSpec.Hello, ScalaTest!.deeeeeeeeep.even deeeeeeeeeper.test"].errors[1].line)
      assert.is_not_nil(results["com.example.FreeSpec.Hello, ScalaTest!.deeeeeeeeep.even deeeeeeeeeper.test"].errors[1].message:match("1 did not equal 2"))

      assert.are.equal(TEST_FAILED, results["com.example.FreeSpec.failing test"].status)
      assert.are.equal(21, results["com.example.FreeSpec.failing test"].errors[1].line)

      assert.are.equal(TEST_FAILED, results["com.example.FreeSpec.deeply.nested"].status)
      assert.are.equal(25, results["com.example.FreeSpec.deeply.nested"].errors[1].line)

      assert.are.equal(TEST_FAILED, results["com.example.FreeSpec.failing"].status)
      assert.are.equal(29, results["com.example.FreeSpec.failing"].errors[1].line)
      assert.is_not_nil(results["com.example.FreeSpec.failing"].errors[1].message:match("RuntimeException: boom"))

      assert.are.equal(TEST_FAILED, results["com.example.FreeSpec.custom exception"].status)
      assert.is_nil(results["com.example.FreeSpec.custom exception"].errors[1].line)
      assert.is_not_nil(results["com.example.FreeSpec.custom exception"].errors[1].message:match("com.example.Babbah"))
    end)

    it("parses FunSuite bloop output with pass, failure and crashes", function()
      local tree = mk_tree({
        {
          type = "test",
          id = "com.example.FunSuiteSpec.Hello, & ScalaTest!",
          name = '"Hello, & ScalaTest!"',
          path = "/project/src/test/scala/com/example/FunSuiteSpec.scala",
        },
        {
          type = "test",
          id = "com.example.FunSuiteSpec.failing test",
          name = '"failing test"',
          path = "/project/src/test/scala/com/example/FunSuiteSpec.scala",
        },
        {
          type = "test",
          id = "com.example.FunSuiteSpec.crashing test",
          name = '"crashing test"',
          path = "/project/src/test/scala/com/example/FunSuiteSpec.scala",
        },
        {
          type = "test",
          id = "com.example.FunSuiteSpec.crashing with custom exception",
          name = '"crashing with custom exception"',
          path = "/project/src/test/scala/com/example/FunSuiteSpec.scala",
        },
      })

      local output = [[
FunSuiteSpec:
- Hello, & ScalaTest!
- failing test *** FAILED ***
  1 did not equal 2 (FunSuiteSpec.scala:15)
- crashing test *** FAILED ***
  java.lang.RuntimeException: kaboom
  at com.example.FunSuiteSpec.testFun$proxy3$1(FunSuiteSpec.scala:18)
  at com.example.FunSuiteSpec.$init$$$anonfun$3(FunSuiteSpec.scala:17)
  at org.scalatest.Transformer.apply$$anonfun$1(Transformer.scala:22)
  ...
- crashing with custom exception *** FAILED ***
  com.example.Boom$: Boom!
  ...
Execution took 1ms
4 tests, 1 passed, 3 failed
]]

      local results = scalatest.parse_stdout_results(output, tree)

      assert.are.equal(TEST_PASSED, results["com.example.FunSuiteSpec.Hello, & ScalaTest!"].status)

      assert.are.equal(TEST_FAILED, results["com.example.FunSuiteSpec.failing test"].status)
      assert.are.equal(14, results["com.example.FunSuiteSpec.failing test"].errors[1].line)
      assert.are.equal("1 did not equal 2", results["com.example.FunSuiteSpec.failing test"].errors[1].message)

      assert.are.equal(TEST_FAILED, results["com.example.FunSuiteSpec.crashing test"].status)
      assert.are.equal(17, results["com.example.FunSuiteSpec.crashing test"].errors[1].line)
      assert.is_not_nil(results["com.example.FunSuiteSpec.crashing test"].errors[1].message:match("RuntimeException: kaboom"))

      assert.are.equal(TEST_FAILED, results["com.example.FunSuiteSpec.crashing with custom exception"].status)
      assert.is_nil(results["com.example.FunSuiteSpec.crashing with custom exception"].errors[1].line)
      assert.is_not_nil(results["com.example.FunSuiteSpec.crashing with custom exception"].errors[1].message:match("com.example.Boom"))
    end)

    it("parses AnyFlatSpec bloop output with should-style names", function()
      local tree = mk_tree({
        {
          type = "test",
          id = "com.example.FlatSpec.pop values in last-in-first-out order",
          name = '"pop values in last-in-first-out order"',
          path = "/project/src/test/scala/com/example/FlatSpec.scala",
        },
        {
          type = "test",
          id = "com.example.FlatSpec.throw NoSuchElementException if an empty stack is popped",
          name = '"throw NoSuchElementException if an empty stack is popped"',
          path = "/project/src/test/scala/com/example/FlatSpec.scala",
        },
        {
          type = "test",
          id = "com.example.FlatSpec.fail",
          name = '"fail"',
          path = "/project/src/test/scala/com/example/FlatSpec.scala",
        },
        {
          type = "test",
          id = "com.example.FlatSpec.crash",
          name = '"crash"',
          path = "/project/src/test/scala/com/example/FlatSpec.scala",
        },
      })

      local output = [[
FlatSpec:
A Stack
- should pop values in last-in-first-out order
- should throw NoSuchElementException if an empty stack is popped
- should fail *** FAILED ***
  1 did not equal 2 (FlatSpec.scala:31)
- should crash *** FAILED ***
  java.lang.RuntimeException: boom
  at com.example.FlatSpec.testFun$proxy4$1(FlatSpec.scala:35)
  at com.example.FlatSpec.$init$$$anonfun$4(FlatSpec.scala:34)
  at org.scalatest.Transformer.apply$$anonfun$1(Transformer.scala:22)
  at org.scalatest.OutcomeOf.outcomeOf(OutcomeOf.scala:85)
  at org.scalatest.OutcomeOf.outcomeOf$(OutcomeOf.scala:31)
  at org.scalatest.OutcomeOf$.outcomeOf(OutcomeOf.scala:104)
  at org.scalatest.Transformer.apply(Transformer.scala:22)
  at org.scalatest.Transformer.apply(Transformer.scala:21)
  at org.scalatest.flatspec.AnyFlatSpecLike$$anon$5.apply(AnyFlatSpecLike.scala:1717)
  at org.scalatest.TestSuite.withFixture(TestSuite.scala:196)
  ...
Execution took 18ms
4 tests, 2 passed, 2 failed
]]

      local results = scalatest.parse_stdout_results(output, tree)

      assert.are.equal(TEST_PASSED, results["com.example.FlatSpec.pop values in last-in-first-out order"].status)
      assert.are.equal(TEST_PASSED, results["com.example.FlatSpec.throw NoSuchElementException if an empty stack is popped"].status)

      assert.are.equal(TEST_FAILED, results["com.example.FlatSpec.fail"].status)
      assert.are.equal(30, results["com.example.FlatSpec.fail"].errors[1].line)
      assert.are.equal("1 did not equal 2", results["com.example.FlatSpec.fail"].errors[1].message)

      assert.are.equal(TEST_FAILED, results["com.example.FlatSpec.crash"].status)
      assert.are.equal(34, results["com.example.FlatSpec.crash"].errors[1].line)
      assert.is_not_nil(results["com.example.FlatSpec.crash"].errors[1].message:match("RuntimeException: boom"))
    end)

    it("parses AnyFeatureSpec bloop output with Scenario prefixes", function()
      local tree = mk_tree({
        {
          type = "test",
          id = "com.example.FeatureSpec.Authentication.successful login",
          name = '"successful login"',
          path = "/project/src/test/scala/com/example/FeatureSpec.scala",
        },
        {
          type = "test",
          id = "com.example.FeatureSpec.Authentication.failing credential check",
          name = '"failing credential check"',
          path = "/project/src/test/scala/com/example/FeatureSpec.scala",
        },
        {
          type = "test",
          id = "com.example.FeatureSpec.Authentication.unexpected exception",
          name = '"unexpected exception"',
          path = "/project/src/test/scala/com/example/FeatureSpec.scala",
        },
      })

      local output = [[
FeatureSpec:
Feature: Authentication
  Scenario: successful login
  Scenario: failing credential check *** FAILED ***
  401 did not equal 200 (FeatureSpec.scala:14)
  Scenario: unexpected exception *** FAILED ***
  at org.scalatest.OutcomeOf$.outcomeOf(OutcomeOf.scala:104)
  at org.scalatest.Transformer.apply(Transformer.scala:21)
  at com.example.FeatureSpec.fun$proxy1$1$$anonfun$3(FeatureSpec.scala:17)
  java.lang.RuntimeException: featurespec crash
  at com.example.FeatureSpec.testFun$proxy3$1(FeatureSpec.scala:18)
Execution took 12ms
3 tests, 1 passed, 2 failed

================================================================================
Total duration: 12ms
1 failed

Failed:
- com.example.FeatureSpec:
  * Feature: Authentication Scenario: failing credential check - 401 did not equal 200
  * Feature: Authentication Scenario: unexpected exception - java.lang.RuntimeException: featurespec crash
================================================================================
]]

      local results = scalatest.parse_stdout_results(output, tree)

      assert.are.equal(TEST_PASSED, results["com.example.FeatureSpec.Authentication.successful login"].status)

      assert.are.equal(TEST_FAILED, results["com.example.FeatureSpec.Authentication.failing credential check"].status)
      assert.are.equal(13, results["com.example.FeatureSpec.Authentication.failing credential check"].errors[1].line)
      assert.is_not_nil(results["com.example.FeatureSpec.Authentication.failing credential check"].errors[1].message:match("401 did not equal 200"))

      assert.are.equal(TEST_FAILED, results["com.example.FeatureSpec.Authentication.unexpected exception"].status)
      assert.are.equal(16, results["com.example.FeatureSpec.Authentication.unexpected exception"].errors[1].line)
      assert.is_not_nil(
        results["com.example.FeatureSpec.Authentication.unexpected exception"].errors[1].message:match("RuntimeException: featurespec crash")
      )
    end)

    it("strips first-line location suffix from stdout diagnostic messages", function()
      local tree = mk_tree({
        {
          type = "test",
          id = "com.example.FunSuiteSpec.failing test",
          name = '"failing test"',
          path = "/project/src/test/scala/com/example/FunSuiteSpec.scala",
        },
      })

      local output = [[
FunSuiteSpec:
- failing test *** FAILED ***
  1 did not equal 2 (FunSuiteSpec.scala:15)
Execution took 1ms
1 test, 0 passed, 1 failed
]]

      local results = scalatest.parse_stdout_results(output, tree)

      assert.are.equal(TEST_FAILED, results["com.example.FunSuiteSpec.failing test"].status)
      assert.are.equal(14, results["com.example.FunSuiteSpec.failing test"].errors[1].line)
      assert.are.equal("1 did not equal 2", results["com.example.FunSuiteSpec.failing test"].errors[1].message)
    end)

    it("picks the first stack frame for the current test file", function()
      local tree = mk_tree({
        {
          type = "test",
          id = "com.example.FlatSpec.crash",
          name = '"crash"',
          path = "/project/src/test/scala/com/example/FlatSpec.scala",
        },
      })

      local output = [[
FlatSpec:
- should crash *** FAILED ***
  java.lang.RuntimeException: boom
  at com.example.FlatSpec.testFun$proxy4$1(FlatSpec.scala:35)
  at com.example.FlatSpec.$init$$$anonfun$4(FlatSpec.scala:34)
  at org.scalatest.Transformer.apply$$anonfun$1(Transformer.scala:22)
  at org.scalatest.OutcomeOf.outcomeOf(OutcomeOf.scala:85)
  at org.scalatest.OutcomeOf.outcomeOf$(OutcomeOf.scala:31)
  at org.scalatest.OutcomeOf$.outcomeOf(OutcomeOf.scala:104)
  at org.scalatest.Transformer.apply(Transformer.scala:22)
  at org.scalatest.Transformer.apply(Transformer.scala:21)
  at org.scalatest.flatspec.AnyFlatSpecLike$$anon$5.apply(AnyFlatSpecLike.scala:1717)
  at org.scalatest.TestSuite.withFixture(TestSuite.scala:196)
  ...
Execution took 18ms
1 test, 0 passed, 1 failed
]]

      local results = scalatest.parse_stdout_results(output, tree)

      assert.are.equal(TEST_FAILED, results["com.example.FlatSpec.crash"].status)
      assert.are.equal(34, results["com.example.FlatSpec.crash"].errors[1].line)
      assert.is_not_nil(results["com.example.FlatSpec.crash"].errors[1].message:match("RuntimeException: boom"))
    end)
  end)
end)
