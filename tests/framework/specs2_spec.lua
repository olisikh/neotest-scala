local specs2 = require("neotest-scala.framework.specs2")
local H = require("tests.helpers")

describe("specs2", function()
  describe("build_command", function()
    after_each(function()
      H.restore_mocks()
    end)

    it("delegates to utils.build_command", function()
      local called = false
      local captured_args = {}

      H.mock_fn("neotest-scala.build", "command", function(opts)
        called = true
        captured_args = {
          root_path = opts.root_path,
          project = opts.project,
          tree = opts.tree,
          name = opts.name,
          extra_args = opts.extra_args,
        }
        return { "sbt", "test" }
      end)

      local tree = { _data = { type = "test", path = "/test/path.scala" }, data = function(self) return self._data end }
      local result = specs2.build_command({
        root_path = "/root",
        project = "myproject",
        tree = tree,
        name = "testName",
        extra_args = { "-v" },
      })

      assert.is_true(called)
      assert.are.equal("/root", captured_args.root_path)
      assert.are.equal("myproject", captured_args.project)
      assert.are.same(tree, captured_args.tree)
      assert.are.equal("testName", captured_args.name)
      assert.are.same({ "-v" }, captured_args.extra_args)
      assert.are.same({ "sbt", "test" }, result)
    end)

    it("delegates to build.command", function()
      local called = false

      H.mock_fn("neotest-scala.build", "command", function(_)
        called = true
        return { "sbt", "test" }
      end)

      local tree = { _data = { type = "dir", path = "/test/path.scala" }, data = function(self) return self._data end }
      local result = specs2.build_command({
        root_path = "/root",
        project = "myproject",
        tree = tree,
        name = nil,
        extra_args = {},
      })

      assert.is_true(called)
      assert.are.same({ "sbt", "test" }, result)
    end)
  end)

  describe("build_test_result matching", function()
    after_each(function()
      H.restore_mocks()
    end)

    it("handles 'should::' prefix correctly", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function(path)
        return "com.example."
      end)

      local junit_test = {
        namespace = "MySpec",
        name = "should::return true",
      }

      local position = {
        id = "com.example.MySpec.return.true",
        path = "/path/to/MySpec.scala",
      }

      local result = specs2.build_test_result(junit_test, position)
      assert.is_not_nil(result)
    end)

    it("handles 'must::' prefix correctly", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function(path)
        return "com.example."
      end)

      local junit_test = {
        namespace = "MySpec",
        name = "must::be valid",
      }

      local position = {
        id = "com.example.MySpec.be.valid",
        path = "/path/to/MySpec.scala",
      }

      local result = specs2.build_test_result(junit_test, position)
      assert.is_not_nil(result)
    end)

    it("handles '::' separator (converts to '.')", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function(path)
        return "com.example."
      end)

      local junit_test = {
        namespace = "MySpec",
        name = "nested::test::case",
      }

      local position = {
        id = "com.example.MySpec.nested.test.case",
        path = "/path/to/MySpec.scala",
      }

      local result = specs2.build_test_result(junit_test, position)
      assert.is_not_nil(result)
    end)

    it("uses prefix/suffix matching", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function(path)
        return "com.example."
      end)

      local junit_test = {
        namespace = "MySpec",
        name = "test case",
      }

      local position = {
        id = "com.example.MySpec.test.case",
        path = "/path/to/MySpec.scala",
      }

      local result = specs2.build_test_result(junit_test, position)
      assert.is_not_nil(result)
    end)

    it("returns false when prefix does not match", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function(path)
        return "com.other."
      end)

      local junit_test = {
        namespace = "MySpec",
        name = "test case",
      }

      local position = {
        id = "com.example.MySpec.test.case",
        path = "/path/to/MySpec.scala",
      }

      local result = specs2.build_test_result(junit_test, position)
      assert.is_nil(result)
    end)

    it("returns false when suffix does not match", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function(path)
        return "com.example."
      end)

      local junit_test = {
        namespace = "MySpec",
        name = "test case",
      }

      local position = {
        id = "com.example.MySpec.different.test",
        path = "/path/to/MySpec.scala",
      }

      local result = specs2.build_test_result(junit_test, position)
      assert.is_nil(result)
    end)

    it("handles combined should:: and :: separators", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function(path)
        return "com.example."
      end)

      local junit_test = {
        namespace = "MySpec",
        name = "should::nested::be valid",
      }

      local position = {
        id = "com.example.MySpec.nested.be.valid",
        path = "/path/to/MySpec.scala",
      }

      local result = specs2.build_test_result(junit_test, position)
      assert.is_not_nil(result)
    end)

    it("handles combined must:: and :: separators", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function(path)
        return "com.example."
      end)

      local junit_test = {
        namespace = "MySpec",
        name = "must::nested::work correctly",
      }

      local position = {
        id = "com.example.MySpec.nested.work.correctly",
        path = "/path/to/MySpec.scala",
      }

      local result = specs2.build_test_result(junit_test, position)
      assert.is_not_nil(result)
    end)
  end)

  describe("parse_stdout_results", function()
    it("marks crashing tests with '!' marker as failed", function()
      local output = [[
MutableSpec

HelloWereld
  + Hello, Specs2!
  x failing test
[E]    1 != 2 (MutableSpec.scala:12)
  and
    + a passing nested test
    x a failing nested test
[E]      hello is not the same as 'world' (MutableSpec.scala:19)
    ! a crashing test
[E]      java.lang.RuntimeException: babbahh (MutableSpec.scala:22)com.example.MutableSpec.$init$

5 tests, 2 passed, 2 failed, 1 errors
]]

      local nodes = {
        {
          data = function()
            return {
              id = "com.example.MutableSpec.HelloWereld.Hello.Specs2!",
              type = "test",
              name = "\"Hello, Specs2!\"",
            }
          end,
        },
        {
          data = function()
            return {
              id = "com.example.MutableSpec.HelloWereld.failing.test",
              type = "test",
              name = "\"failing test\"",
            }
          end,
        },
        {
          data = function()
            return {
              id = "com.example.MutableSpec.HelloWereld.and.a.passing.nested.test",
              type = "test",
              name = "\"a passing nested test\"",
            }
          end,
        },
        {
          data = function()
            return {
              id = "com.example.MutableSpec.HelloWereld.and.a.failing.nested.test",
              type = "test",
              name = "\"a failing nested test\"",
            }
          end,
        },
        {
          data = function()
            return {
              id = "com.example.MutableSpec.HelloWereld.and.a.crashing.test",
              type = "test",
              name = "\"a crashing test\"",
            }
          end,
        },
      }

      local tree = {
        iter_nodes = function()
          return ipairs(nodes)
        end,
      }

      local results = specs2.parse_stdout_results(output, tree)

      assert.are.equal(TEST_FAILED, results["com.example.MutableSpec.HelloWereld.and.a.crashing.test"].status)
      assert.are.equal(21, results["com.example.MutableSpec.HelloWereld.and.a.crashing.test"].errors[1].line)
      assert.is_truthy(results["com.example.MutableSpec.HelloWereld.and.a.crashing.test"].errors[1].message:find("RuntimeException", 1, true))
    end)
  end)
end)
