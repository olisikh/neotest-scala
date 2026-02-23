package.loaded["neotest.lib"] = package.loaded["neotest.lib"] or {
  files = {
    read_lines = function(_)
      return { "package com.example" }
    end,
  },
}

local scalatest = require("neotest-scala.framework.scalatest")
local H = require("tests.helpers")

describe("scalatest", function()
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

  describe("match_test", function()
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

      local result = scalatest.match_test(junit_test, position)

      assert.is_true(result)
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

      local result = scalatest.match_test(junit_test, position)

      assert.is_true(result)
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

      local result = scalatest.match_test(junit_test, position)

      assert.is_false(result)
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

      local result = scalatest.match_test(junit_test, position)

      assert.is_true(result)
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

      local result = scalatest.match_test(junit_test, position)

      assert.is_true(result)
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

      local result = scalatest.match_test(junit_test, position)

      assert.is_false(result)
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

      local result = scalatest.match_test(junit_test, position)

      assert.is_true(result)
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

      local result = scalatest.match_test(junit_test, position)

      assert.is_true(result)
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

      local result = scalatest.match_test(junit_test, position)

      assert.is_true(result)
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

      local result = scalatest.match_test(junit_test, position)

      assert.is_true(result)
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

      local result = scalatest.match_test(junit_test, position)

      assert.is_false(result)
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

      local result = scalatest.match_test(junit_test, position)

      assert.is_true(result)
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
  end)
end)
