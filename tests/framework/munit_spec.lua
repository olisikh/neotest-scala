local H = require("tests.helpers")

package.loaded["neotest.lib"] = package.loaded["neotest.lib"] or {
  files = {
    read_lines = function(_)
      return { "package com.example" }
    end,
  },
}

local fw = require("neotest-scala.framework")
local munit = require("neotest-scala.framework.munit")

local function mock_tree(data, parent, children)
  local tree = {}
  local _data = data
  local _parent = parent
  local _children = children or {}

  function tree:data()
    return _data
  end

  function tree:parent()
    return _parent
  end

  function tree:children()
    return _children
  end

  function tree:iter_nodes()
    local nodes = { tree }
    for _, child in ipairs(_children) do
      table.insert(nodes, child)
    end
    local i = 0
    return function()
      i = i + 1
      if nodes[i] then
        return i, nodes[i]
      end
    end
  end

  return tree
end

describe("munit", function()
  local captured_test_path

  before_each(function()
    captured_test_path = nil
    H.mock_fn("neotest-scala.utils", "get_package_name", function(path)
      if path and path:match("%.scala$") then
        return "com.example."
      end
      return ""
    end)
    H.mock_fn("neotest-scala.utils", "get_file_name", function(path)
      local parts = {}
      for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
      end
      return parts[#parts]
    end)
    H.mock_fn("neotest-scala.build", "command_with_path", function(root_path, project, test_path, extra_args)
      captured_test_path = test_path
      return { "sbt", project .. "/testOnly", test_path }
    end)
  end)

  after_each(function()
    H.restore_mocks()
  end)

  describe("build_test_path", function()
    describe("for single test (type == 'test')", function()
      it("builds path with package, spec name, and test name", function()
        local namespace_tree = mock_tree({
          type = "namespace",
          name = "MySpec",
          path = "/project/src/test/scala/com/example/MySpec.scala",
        })

        local test_tree = mock_tree({
          type = "test",
          name = '"should pass"',
          path = "/project/src/test/scala/com/example/MySpec.scala",
        }, namespace_tree)

        munit.build_command("/project", "root", test_tree, "should pass", {})

        assert.are.equal("com.example.MySpec.should pass", captured_test_path)
      end)

      it("handles nested tests with parent test", function()
        local namespace_tree = mock_tree({
          type = "namespace",
          name = "NestedSpec",
          path = "/project/src/test/scala/com/example/NestedSpec.scala",
        })

        local parent_test_tree = mock_tree({
          type = "test",
          name = '"parent test"',
          path = "/project/src/test/scala/com/example/NestedSpec.scala",
        }, namespace_tree)

        local nested_test_tree = mock_tree({
          type = "test",
          name = '"child test"',
          path = "/project/src/test/scala/com/example/NestedSpec.scala",
        }, parent_test_tree)

        munit.build_command("/project", "root", nested_test_tree, "child test", {})

        assert.are.equal("com.example.NestedSpec.parent test.child test", captured_test_path)
      end)
    end)

    describe("for namespace (type == 'namespace')", function()
      it("builds path with package and spec name with wildcard", function()
        local namespace_tree = mock_tree({
          type = "namespace",
          name = "MySpec",
          path = "/project/src/test/scala/com/example/MySpec.scala",
        })

        munit.build_command("/project", "root", namespace_tree, "MySpec", {})

        assert.are.equal("com.example.MySpec.*", captured_test_path)
      end)

      it("returns nil when package cannot be determined", function()
        H.mock_fn("neotest-scala.utils", "get_package_name", function()
          return nil
        end)

        local namespace_tree = mock_tree({
          type = "namespace",
          name = "NoPackageSpec",
          path = "/project/src/test/scala/NoPackageSpec.scala",
        })

        munit.build_command("/project", "root", namespace_tree, "NoPackageSpec", {})

        assert.is_nil(captured_test_path)
      end)
    end)

    describe("for file (type == 'file')", function()
      it("builds path with package wildcard", function()
        local namespace_child = mock_tree({
          type = "namespace",
          name = "FileSpec",
          path = "/project/src/test/scala/com/example/FileSpec.scala",
        })

        local file_tree = mock_tree({
          type = "file",
          name = "FileSpec.scala",
          path = "/project/src/test/scala/com/example/FileSpec.scala",
        }, nil, { namespace_child })

        munit.build_command("/project", "root", file_tree, "FileSpec.scala", {})

        assert.are.equal("com.example.*", captured_test_path)
      end)
    end)

    describe("for dir (type == 'dir')", function()
      it("returns wildcard for directory", function()
        local dir_tree = mock_tree({
          type = "dir",
          name = "scala",
          path = "/project/src/test/scala",
        })

        munit.build_command("/project", "root", dir_tree, "scala", {})

        assert.are.equal("*", captured_test_path)
      end)
    end)
  end)

  describe("build_test_result", function()
    describe("parses stacktrace correctly", function()
      it("extracts error message from error_stacktrace", function()
        local junit_test = {
          error_stacktrace = "munit.FailException: assertion failed\n  at /path/to/MySpec.scala:42",
        }
        local position = {
          path = "/project/src/test/scala/com/example/MySpec.scala",
        }

        local result = munit.build_test_result(junit_test, position)

        assert.are.equal(fw.TEST_FAILED, result.status)
        assert.is_not_nil(result.errors)
        assert.are.equal(1, #result.errors)
        assert.is_not_nil(result.errors[1].message)
      end)

      it("extracts error message from error_message when no stacktrace", function()
        local junit_test = {
          error_message = "Test failed: expected true but was false",
        }
        local position = {
          path = "/project/src/test/scala/com/example/MySpec.scala",
        }

        local result = munit.build_test_result(junit_test, position)

        assert.are.equal(fw.TEST_FAILED, result.status)
        assert.are.equal("Test failed: expected true but was false", result.errors[1].message)
      end)

      it("returns passed status when no error", function()
        local junit_test = {}
        local position = {
          path = "/project/src/test/scala/com/example/MySpec.scala",
        }

        local result = munit.build_test_result(junit_test, position)

        assert.are.equal(fw.TEST_PASSED, result.status)
        assert.is_nil(result.errors)
      end)
    end)

    describe("extracts line number from stacktrace", function()
      it("extracts line number from stacktrace pattern", function()
        local junit_test = {
          error_stacktrace = "munit.FailException: failed\n  at com.example.MySpec.test(MySpec.scala:25)",
        }
        local position = {
          path = "/project/src/test/scala/com/example/MySpec.scala",
        }

        local result = munit.build_test_result(junit_test, position)

        assert.are.equal(fw.TEST_FAILED, result.status)
        assert.are.equal(24, result.errors[1].line)
      end)

      it("handles different line numbers", function()
        local junit_test = {
          error_stacktrace = "error at (MySpec.scala:100)",
        }
        local position = {
          path = "/project/src/test/scala/com/example/MySpec.scala",
        }

        local result = munit.build_test_result(junit_test, position)

        assert.are.equal(99, result.errors[1].line)
      end)

      it("returns nil line when pattern not found", function()
        local junit_test = {
          error_stacktrace = "some error without line number",
        }
        local position = {
          path = "/project/src/test/scala/com/example/MySpec.scala",
        }

        local result = munit.build_test_result(junit_test, position)

        assert.are.equal(fw.TEST_FAILED, result.status)
        assert.is_nil(result.errors[1].line)
      end)
    end)

    describe("strips file path from message", function()
      it("removes file path prefix from error message", function()
        local junit_test = {
          error_stacktrace = "munit.FailException: /some/path/MySpec.scala:42 assertion failed",
        }
        local position = {
          path = "/project/src/test/scala/com/example/MySpec.scala",
        }

        local result = munit.build_test_result(junit_test, position)

        assert.is_not_nil(result.errors[1].message)
        assert.is_nil(result.errors[1].message:match("/some/path/MySpec%.scala:%d+"))
      end)
    end)
  end)
end)
