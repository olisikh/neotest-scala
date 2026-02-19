local zio_test = require("neotest-scala.framework.zio-test")
require("neotest-scala.framework")
local H = require("tests.helpers")

describe("zio-test", function()
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

      local result = zio_test.build_command(root_path, project, tree, name, extra_args)

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

      local result = zio_test.build_command("/root", "myproject", {}, "TestSpec", {})

      assert.are.same(expected_command, result)
    end)

    it("handles nil extra_args", function()
      local called_with = nil
      H.mock_fn("neotest-scala.utils", "build_command", function(root_path, project, tree, name, extra_args)
        called_with = { root_path, project, tree, name, extra_args }
        return {}
      end)

      zio_test.build_command("/root", "project", {}, "Test", nil)

      assert(called_with, "build_command should have been called")
      assert.is_nil(called_with[5])
    end)
  end)

  describe("build_test_result", function()
    before_each(function()
      H.mock_fn("neotest-scala.utils", "get_file_name", function(path)
        local parts = {}
        for part in path:gmatch("[^/]+") do
          table.insert(parts, part)
        end
        return parts[#parts]
      end)
    end)

    after_each(function()
      H.restore_mocks()
    end)

    describe("with error_message present", function()
      it("extracts error message from error_message", function()
        local junit_test = {
          error_message = "Some error header\nactual error message here\nat /path/to/ZioSpec.scala:42\ntrailing",
        }
        local position = {
          path = "/project/src/test/scala/com/example/ZioSpec.scala",
        }

        local result = zio_test.build_test_result(junit_test, position)

        assert.are.equal("failed", result.status)
        assert.is_not_nil(result.errors)
        assert.are.equal(1, #result.errors)
        assert.is_not_nil(result.errors[1].message)
      end)

      it("extracts line number from ZIO-specific stacktrace format in error_message", function()
        local junit_test = {
          error_message = "Test failed\nerror details\nat /some/path/ZioSpec.scala:25\ntrailing",
        }
        local position = {
          path = "/project/src/test/scala/com/example/ZioSpec.scala",
        }

        local result = zio_test.build_test_result(junit_test, position)

        assert.are.equal("failed", result.status)
        assert.are.equal(24, result.errors[1].line)
      end)

      it("extracts line number from parenthesized format in error_message", function()
        local junit_test = {
          error_message = "Test failed\n(ZioSpec.scala:100)\ntrailing",
        }
        local position = {
          path = "/project/src/test/scala/com/example/ZioSpec.scala",
        }

        local result = zio_test.build_test_result(junit_test, position)

        assert.are.equal("failed", result.status)
        assert.are.equal(99, result.errors[1].line)
      end)

      it("includes last_line in message when line number not found", function()
        local junit_test = {
          error_message = "Test failed\nerror details\nno line info here\ntrailing",
        }
        local position = {
          path = "/project/src/test/scala/com/example/ZioSpec.scala",
        }

        local result = zio_test.build_test_result(junit_test, position)

        assert.are.equal("failed", result.status)
        assert.is_nil(result.errors[1].line)
        assert.is_not_nil(result.errors[1].message:match("no line info here"))
      end)
    end)

    describe("with only error_stacktrace (falls back)", function()
      it("extracts line number from error_stacktrace when no error_message", function()
        local junit_test = {
          error_stacktrace = "zio.test.TestFailure: assertion failed\nat com.example.ZioSpec.test(ZioSpec.scala:42)",
        }
        local position = {
          path = "/project/src/test/scala/com/example/ZioSpec.scala",
        }

        local result = zio_test.build_test_result(junit_test, position)

        assert.are.equal("failed", result.status)
        assert.are.equal(41, result.errors[1].line)
      end)

      it("uses error_stacktrace as message when no error_message", function()
        local junit_test = {
          error_stacktrace = "full stacktrace content here",
        }
        local position = {
          path = "/project/src/test/scala/com/example/ZioSpec.scala",
        }

        local result = zio_test.build_test_result(junit_test, position)

        assert.are.equal("failed", result.status)
        assert.are.equal("full stacktrace content here", result.errors[1].message)
      end)

      it("returns nil line when stacktrace pattern not found", function()
        local junit_test = {
          error_stacktrace = "some error without file reference",
        }
        local position = {
          path = "/project/src/test/scala/com/example/ZioSpec.scala",
        }

        local result = zio_test.build_test_result(junit_test, position)

        assert.are.equal("failed", result.status)
        assert.is_nil(result.errors[1].line)
      end)
    end)

    describe("parses ZIO-specific stacktrace format", function()
      it("extracts line from 'at /path/File.scala:N' format", function()
        local junit_test = {
          error_message = "header\nmessage\nat /project/src/ZioSpec.scala:15\ntrailing",
        }
        local position = {
          path = "/project/src/ZioSpec.scala",
        }

        local result = zio_test.build_test_result(junit_test, position)

        assert.are.equal(14, result.errors[1].line)
      end)

      it("extracts line from '(File.scala:N)' format", function()
        local junit_test = {
          error_message = "error occurred\n(ZioSpec.scala:30)\ntrailing",
        }
        local position = {
          path = "/some/path/ZioSpec.scala",
        }

        local result = zio_test.build_test_result(junit_test, position)

        assert.are.equal(29, result.errors[1].line)
      end)

      it("handles multi-line ZIO error messages", function()
        local junit_test = {
          error_message = "Test failure header\nAssertion failed\nExpected: true\nActual: false\nat /path/ZioSpec.scala:50\ntrailing",
        }
        local position = {
          path = "/path/ZioSpec.scala",
        }

        local result = zio_test.build_test_result(junit_test, position)

        assert.are.equal("failed", result.status)
        assert.are.equal(49, result.errors[1].line)
        assert.is_not_nil(result.errors[1].message:match("Assertion failed"))
      end)
    end)

    describe("extracts line number from stacktrace", function()
      it("handles different line numbers correctly", function()
        local junit_test = {
          error_stacktrace = "error at (ZioSpec.scala:1)",
        }
        local position = {
          path = "/project/ZioSpec.scala",
        }

        local result = zio_test.build_test_result(junit_test, position)

        assert.are.equal(0, result.errors[1].line)
      end)

      it("handles large line numbers", function()
        local junit_test = {
          error_stacktrace = "error at (ZioSpec.scala:9999)",
        }
        local position = {
          path = "/project/ZioSpec.scala",
        }

        local result = zio_test.build_test_result(junit_test, position)

        assert.are.equal(9998, result.errors[1].line)
      end)
    end)

    describe("returns passed status when no error", function()
      it("returns passed when junit_test is empty", function()
        local junit_test = {}
        local position = {
          path = "/project/src/test/scala/com/example/ZioSpec.scala",
        }

        local result = zio_test.build_test_result(junit_test, position)

        assert.are.equal("passed", result.status)
        assert.is_nil(result.errors)
      end)

      it("returns passed when no error fields present", function()
        local junit_test = {
          name = "testName",
          time = "0.5",
        }
        local position = {
          path = "/project/src/test/scala/com/example/ZioSpec.scala",
        }

        local result = zio_test.build_test_result(junit_test, position)

        assert.are.equal("passed", result.status)
        assert.is_nil(result.errors)
      end)
    end)
  end)
end)
