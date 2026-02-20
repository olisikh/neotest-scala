local scalatest = require("neotest-scala.framework.scalatest")
local H = require("tests.helpers")

describe("scalatest", function()
  describe("build_command", function()
    after_each(function()
      H.restore_mocks()
    end)

    it("delegates to utils.build_command with all arguments", function()
      local called_with = nil
      H.mock_fn("neotest-scala.utils", "build_command", function(root_path, project, tree, name, extra_args)
        called_with = { root_path, project, tree, name, extra_args }
        return { "mocked", "command" }
      end)

      local root_path = "/project/root"
      local project = "myproject"
      local tree = { data = { type = "test" } }
      local name = "MyTestClass"
      local extra_args = { "--verbose" }

      local result = scalatest.build_command(root_path, project, tree, name, extra_args)

      assert(called_with, "build_command should have been called")
      assert.are.equal(root_path, called_with[1])
      assert.are.equal(project, called_with[2])
      assert.are.same(tree, called_with[3])
      assert.are.equal(name, called_with[4])
      assert.are.same(extra_args, called_with[5])
      assert.are.same({ "mocked", "command" }, result)
    end)

    it("returns the result from utils.build_command unchanged", function()
      local expected_command = { "sbt", "myproject/testOnly", "com.example.TestSpec" }
      H.mock_fn("neotest-scala.utils", "build_command", function()
        return expected_command
      end)

      local result = scalatest.build_command("/root", "myproject", {}, "TestSpec", {})

      assert.are.same(expected_command, result)
    end)

    it("handles nil extra_args", function()
      local called_with = nil
      H.mock_fn("neotest-scala.utils", "build_command", function(root_path, project, tree, name, extra_args)
        called_with = { root_path, project, tree, name, extra_args }
        return {}
      end)

      scalatest.build_command("/root", "project", {}, "Test", nil)

      assert(called_with, "build_command should have been called")
      assert.is_nil(called_with[5])
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

    it("converts spaces to dots in test names", function()
      local junit_test = {
        name = "should do something cool",
        namespace = "MySpec",
      }

      local position = {
        path = "/path/to/MySpec.scala",
        id = "com.example.MySpec.should.do.something.cool",
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
        id = "com.example.ValidatorSpec.should.return.true.when.input.is.valid",
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
