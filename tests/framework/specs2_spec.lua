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

  describe("match_test", function()
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

      local result = specs2.match_test(junit_test, position)
      assert.is_true(result)
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

      local result = specs2.match_test(junit_test, position)
      assert.is_true(result)
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

      local result = specs2.match_test(junit_test, position)
      assert.is_true(result)
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

      local result = specs2.match_test(junit_test, position)
      assert.is_true(result)
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

      local result = specs2.match_test(junit_test, position)
      assert.is_false(result)
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

      local result = specs2.match_test(junit_test, position)
      assert.is_false(result)
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

      local result = specs2.match_test(junit_test, position)
      assert.is_true(result)
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

      local result = specs2.match_test(junit_test, position)
      assert.is_true(result)
    end)
  end)
end)
