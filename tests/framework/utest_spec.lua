package.loaded["neotest.lib"] = package.loaded["neotest.lib"] or {}
package.loaded["neotest.lib"].treesitter = package.loaded["neotest.lib"].treesitter or {}

local parse_positions_calls = {}
package.loaded["neotest.lib"].treesitter.parse_positions = function(path, query, opts)
  table.insert(parse_positions_calls, { path = path, query = query, opts = opts })
  return { path = path, query = query, opts = opts }
end

local utest = require("neotest-scala.framework.utest")
require("neotest-scala.framework")
local H = require("tests.helpers")

-- Helper to create mock neotest.Tree-like objects
local function mock_tree(data, parent, children)
  local tree = {
    _data = data,
    _parent = parent,
    _children = children or {},
  }

  function tree:data()
    return self._data
  end

  function tree:parent()
    return self._parent
  end

  function tree:children()
    return self._children
  end

  function tree:iter_nodes()
    local nodes = { self }
    for _, child in ipairs(self._children) do
      table.insert(nodes, child)
      for _, nested in ipairs(child._children or {}) do
        table.insert(nodes, nested)
      end
    end
    local i = 0
    return function()
      i = i + 1
      if nodes[i] then
        return i, nodes[i]
      end
      return nil
    end
  end

  return tree
end

describe("utest", function()
  describe("discover_positions", function()
    before_each(function()
      H.restore_mocks()
      parse_positions_calls = {}
    end)

    it("supports interpolated test names", function()
      local tree = utest.discover_positions({
        path = "/project/src/test/scala/com/example/UTestSuite.scala",
        content = [[
          import utest.*

          object UTestSuite extends TestSuite {
            val baseName = "utest"
            val tests = Tests {
              test(s"$baseName success") {
                assert(1 == 1)
              }
            }
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.are.equal(1, #parse_positions_calls)
      assert.is_true(parse_positions_calls[1].query:find("interpolated_string_expression", 1, true) ~= nil)
    end)

    it("supports anonymous infix and block tests", function()
      local tree = utest.discover_positions({
        path = "/project/src/test/scala/com/example/UTestSuite.scala",
        content = [[
          import utest.*

          object UTestSuite extends TestSuite {
            val tests = Tests {
              test - assert(1 == 2)
              test - {
                assert(1 == 2)
              }
              test {
                assert(1 == 2)
              }
            }
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.are.equal(1, #parse_positions_calls)
      assert.is_true(parse_positions_calls[1].query:find("infix_expression", 1, true) ~= nil)
      assert.is_true(parse_positions_calls[1].query:find("(block)", 1, true) ~= nil)
    end)

    it("builds unique ids for anonymous tests to keep numeric mapping stable", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function()
        return "com.example."
      end)

      utest.discover_positions({
        path = "/project/src/test/scala/com/example/UTestSuite.scala",
        content = [[
          import utest.*
          object UTestSuite extends TestSuite {
            val tests = Tests { test - assert(1 == 2) }
          }
        ]],
      })

      local position_id = parse_positions_calls[1].opts.position_id

      local parents = {
        {
          type = "namespace",
          name = "UTestSuite",
          path = "/project/src/test/scala/com/example/UTestSuite.scala",
        },
      }
      local named_id = position_id({
        type = "test",
        name = '"named"',
        range = { 8, 0, 8, 10 },
      }, parents)
      local anonymous_id_1 = position_id({
        type = "test",
        name = "test",
        range = { 12, 0, 12, 10 },
      }, parents)
      local anonymous_id_2 = position_id({
        type = "test",
        name = "test",
        range = { 13, 0, 13, 10 },
      }, parents)

      assert.are_not.equal(anonymous_id_1, anonymous_id_2)
      assert.is_true(anonymous_id_1:find(".__anonymous_12_0", 1, true) ~= nil)
      assert.are.equal("com.example.UTestSuite.named", named_id)
    end)
  end)

  describe("build_command", function()
    after_each(function()
      H.restore_mocks()
    end)

    describe("for single test (type == 'test')", function()
      it("builds path with package.namespace.testname when parent is namespace", function()
        local test_path_arg = nil
        H.mock_fn("neotest-scala.build", "command_with_path", function(opts)
          test_path_arg = opts.test_path
          return { "sbt", "project/testOnly", opts.test_path }
        end)
        H.mock_fn("neotest-scala.utils", "get_package_name", function(_)
          return "com.example."
        end)

        local namespace_data = {
          type = "namespace",
          name = "MySuite",
          path = "/path/to/MySuite.scala",
        }
        local namespace_tree = mock_tree(namespace_data)

        local test_data = {
          type = "test",
          name = "myTest",
          path = "/path/to/MySuite.scala",
        }
        local test_tree = mock_tree(test_data, namespace_tree)

        utest.build_command({
          root_path = "/root",
          project = "myproject",
          tree = test_tree,
          name = "myTest",
          extra_args = {},
        })

        assert.are.equal("com.example.MySuite.myTest", test_path_arg)
      end)

      it("builds path for nested tests", function()
        local test_path_arg = nil
        H.mock_fn("neotest-scala.build", "command_with_path", function(opts)
          test_path_arg = opts.test_path
          return { "sbt", "project/testOnly", opts.test_path }
        end)
        H.mock_fn("neotest-scala.utils", "get_package_name", function(_)
          return "com.example."
        end)
        H.mock_fn("neotest-scala.utils", "get_position_name", function(pos)
          return pos.name
        end)

        local namespace_data = {
          type = "namespace",
          name = "MySuite",
          path = "/path/to/MySuite.scala",
        }
        local namespace_tree = mock_tree(namespace_data)

        local parent_test_data = {
          type = "test",
          name = "parentTest",
          path = "/path/to/MySuite.scala",
        }
        local parent_test_tree = mock_tree(parent_test_data, namespace_tree)

        local nested_test_data = {
          type = "test",
          name = "nestedTest",
          path = "/path/to/MySuite.scala",
        }
        local nested_test_tree = mock_tree(nested_test_data, parent_test_tree)

        utest.build_command({
          root_path = "/root",
          project = "myproject",
          tree = nested_test_tree,
          name = "nestedTest",
          extra_args = {},
        })

        assert.are.equal("com.example.MySuite.parentTest.nestedTest", test_path_arg)
      end)

      it("falls back to suite path for interpolated test names", function()
        local test_path_arg = nil
        H.mock_fn("neotest-scala.build", "command_with_path", function(opts)
          test_path_arg = opts.test_path
          return { "sbt", "project/testOnly", opts.test_path }
        end)
        H.mock_fn("neotest-scala.utils", "get_package_name", function(_)
          return "com.example."
        end)

        local namespace_data = {
          type = "namespace",
          name = "UTestInterpolatedSuite",
          path = "/path/to/UTestInterpolatedSuite.scala",
        }
        local namespace_tree = mock_tree(namespace_data)

        local test_data = {
          type = "test",
          name = 's"$baseName success"',
          path = "/path/to/UTestInterpolatedSuite.scala",
        }
        local test_tree = mock_tree(test_data, namespace_tree)

        utest.build_command({
          root_path = "/root",
          project = "myproject",
          tree = test_tree,
          name = "$baseName success",
          extra_args = {},
        })

        assert.are.equal("com.example.UTestInterpolatedSuite", test_path_arg)
      end)

      it("falls back to suite path for anonymous infix tests", function()
        local test_path_arg = nil
        H.mock_fn("neotest-scala.build", "command_with_path", function(opts)
          test_path_arg = opts.test_path
          return { "sbt", "project/testOnly", opts.test_path }
        end)
        H.mock_fn("neotest-scala.utils", "get_package_name", function(_)
          return "com.example."
        end)

        local namespace_data = {
          type = "namespace",
          name = "UTestAnonymousSuite",
          path = "/path/to/UTestAnonymousSuite.scala",
        }
        local namespace_tree = mock_tree(namespace_data)

        local test_data = {
          type = "test",
          name = "test",
          path = "/path/to/UTestAnonymousSuite.scala",
        }
        local test_tree = mock_tree(test_data, namespace_tree)

        utest.build_command({
          root_path = "/root",
          project = "myproject",
          tree = test_tree,
          name = "test",
          extra_args = {},
        })

        assert.are.equal("com.example.UTestAnonymousSuite", test_path_arg)
      end)

      it("keeps explicit named test selector when test name is test", function()
        local test_path_arg = nil
        H.mock_fn("neotest-scala.build", "command_with_path", function(opts)
          test_path_arg = opts.test_path
          return { "sbt", "project/testOnly", opts.test_path }
        end)
        H.mock_fn("neotest-scala.utils", "get_package_name", function(_)
          return "com.example."
        end)

        local namespace_data = {
          type = "namespace",
          name = "UTestNamedSuite",
          path = "/path/to/UTestNamedSuite.scala",
        }
        local namespace_tree = mock_tree(namespace_data)

        local test_data = {
          type = "test",
          name = '"test"',
          path = "/path/to/UTestNamedSuite.scala",
        }
        local test_tree = mock_tree(test_data, namespace_tree)

        utest.build_command({
          root_path = "/root",
          project = "myproject",
          tree = test_tree,
          name = "test",
          extra_args = {},
        })

        assert.are.equal("com.example.UTestNamedSuite.test", test_path_arg)
      end)
    end)

    describe("for file (type == 'file')", function()
      it("builds path with brace syntax for multiple suites", function()
        local test_path_arg = nil
        H.mock_fn("neotest-scala.build", "command_with_path", function(opts)
          test_path_arg = opts.test_path
          return { "sbt", "project/testOnly", opts.test_path }
        end)
        H.mock_fn("neotest-scala.utils", "get_package_name", function(_)
          return "com.example."
        end)

        local file_data = {
          type = "file",
          path = "/path/to/Tests.scala",
        }

        local suite1_data = {
          type = "namespace",
          name = "Suite1",
          path = "/path/to/Tests.scala",
        }
        local suite1_tree = mock_tree(suite1_data)

        local suite2_data = {
          type = "namespace",
          name = "Suite2",
          path = "/path/to/Tests.scala",
        }
        local suite2_tree = mock_tree(suite2_data)

        local file_tree = mock_tree(file_data, nil, { suite1_tree, suite2_tree })
        suite1_tree._parent = file_tree
        suite2_tree._parent = file_tree

        utest.build_command({
          root_path = "/root",
          project = "myproject",
          tree = file_tree,
          name = "Tests.scala",
          extra_args = {},
        })

        assert.are.equal("com.example.{Suite1,Suite2}", test_path_arg)
      end)

      it("builds path with brace syntax for single suite", function()
        local test_path_arg = nil
        H.mock_fn("neotest-scala.build", "command_with_path", function(opts)
          test_path_arg = opts.test_path
          return { "sbt", "project/testOnly", opts.test_path }
        end)
        H.mock_fn("neotest-scala.utils", "get_package_name", function(_)
          return "com.example."
        end)

        local file_data = {
          type = "file",
          path = "/path/to/Tests.scala",
        }

        local suite_data = {
          type = "namespace",
          name = "SingleSuite",
          path = "/path/to/Tests.scala",
        }
        local suite_tree = mock_tree(suite_data)

        local file_tree = mock_tree(file_data, nil, { suite_tree })
        suite_tree._parent = file_tree

        utest.build_command({
          root_path = "/root",
          project = "myproject",
          tree = file_tree,
          name = "Tests.scala",
          extra_args = {},
        })

        assert.are.equal("com.example.{SingleSuite}", test_path_arg)
      end)
    end)

    describe("for directory (type == 'dir')", function()
      it("builds path with brace syntax for multiple packages", function()
        local test_path_arg = nil
        H.mock_fn("neotest-scala.build", "command_with_path", function(opts)
          test_path_arg = opts.test_path
          return { "sbt", "project/testOnly", opts.test_path }
        end)
        H.mock_fn("neotest-scala.utils", "get_package_name", function(path)
          if path:match("Suite1") then
            return "com.pkg1."
          elseif path:match("Suite2") then
            return "com.pkg2."
          end
          return "com.default."
        end)

        local dir_data = {
          type = "dir",
          path = "/path/to/tests",
        }

        local suite1_data = {
          type = "namespace",
          name = "Suite1",
          path = "/path/to/tests/Suite1.scala",
        }
        local suite1_tree = mock_tree(suite1_data)

        local suite2_data = {
          type = "namespace",
          name = "Suite2",
          path = "/path/to/tests/Suite2.scala",
        }
        local suite2_tree = mock_tree(suite2_data)

        local dir_tree = mock_tree(dir_data, nil, { suite1_tree, suite2_tree })
        suite1_tree._parent = dir_tree
        suite2_tree._parent = dir_tree

        utest.build_command({
          root_path = "/root",
          project = "myproject",
          tree = dir_tree,
          name = "tests",
          extra_args = {},
        })

        -- Packages should have trailing dot stripped (sub(1, -2))
        assert.are.equal("{com.pkg1,com.pkg2}", test_path_arg)
      end)

      it("deduplicates packages in directory", function()
        local test_path_arg = nil
        H.mock_fn("neotest-scala.build", "command_with_path", function(opts)
          test_path_arg = opts.test_path
          return { "sbt", "project/testOnly", opts.test_path }
        end)
        H.mock_fn("neotest-scala.utils", "get_package_name", function(_)
          return "com.samepkg."
        end)

        local dir_data = {
          type = "dir",
          path = "/path/to/tests",
        }

        local suite1_data = {
          type = "namespace",
          name = "Suite1",
          path = "/path/to/tests/Suite1.scala",
        }
        local suite1_tree = mock_tree(suite1_data)

        local suite2_data = {
          type = "namespace",
          name = "Suite2",
          path = "/path/to/tests/Suite2.scala",
        }
        local suite2_tree = mock_tree(suite2_data)

        local dir_tree = mock_tree(dir_data, nil, { suite1_tree, suite2_tree })
        suite1_tree._parent = dir_tree
        suite2_tree._parent = dir_tree

        utest.build_command({
          root_path = "/root",
          project = "myproject",
          tree = dir_tree,
          name = "tests",
          extra_args = {},
        })

        -- Same package should only appear once
        assert.are.equal("{com.samepkg}", test_path_arg)
      end)
    end)

    describe("delegates to build.command_with_path", function()
      it("passes all arguments correctly", function()
        local called_with = nil
        H.mock_fn("neotest-scala.build", "command_with_path", function(opts)
          called_with = opts
          return { "mocked", "command" }
        end)
        H.mock_fn("neotest-scala.utils", "get_package_name", function(_)
          return "com.example."
        end)

        local root_path = "/project/root"
        local project = "myproject"
        local namespace_data = {
          type = "namespace",
          name = "MySuite",
          path = "/path/to/MySuite.scala",
        }
        local namespace_tree = mock_tree(namespace_data)
        local test_data = {
          type = "test",
          name = "myTest",
          path = "/path/to/MySuite.scala",
        }
        local tree = mock_tree(test_data, namespace_tree)
        local name = "myTest"
        local extra_args = { "--verbose" }

        local result = utest.build_command({
          root_path = root_path,
          project = project,
          tree = tree,
          name = name,
          extra_args = extra_args,
        })

        assert.is_not_nil(called_with)
        assert.are.equal(root_path, called_with.root_path)
        assert.are.equal(project, called_with.project)
        assert.are.same(extra_args, called_with.extra_args)
        assert.are.same({ "mocked", "command" }, result)
      end)

      it("handles nil extra_args", function()
        local called_with = nil
        H.mock_fn("neotest-scala.build", "command_with_path", function(opts)
          called_with = opts
          return {}
        end)
        H.mock_fn("neotest-scala.utils", "get_package_name", function(_)
          return "com.example."
        end)

        local namespace_data = {
          type = "namespace",
          name = "MySuite",
          path = "/path/to/MySuite.scala",
        }
        local namespace_tree = mock_tree(namespace_data)
        local test_data = {
          type = "test",
          name = "myTest",
          path = "/path/to/MySuite.scala",
        }
        local tree = mock_tree(test_data, namespace_tree)

        utest.build_command({
          root_path = "/root",
          project = "project",
          tree = tree,
          name = "Test",
          extra_args = nil,
        })

        assert.is_not_nil(called_with)
        assert.is_nil(called_with.extra_args)
      end)
    end)

    describe("for namespace (type == 'namespace')", function()
      it("builds path with package.namespace", function()
        local test_path_arg = nil
        H.mock_fn("neotest-scala.build", "command_with_path", function(opts)
          test_path_arg = opts.test_path
          return { "sbt", "project/testOnly", opts.test_path }
        end)
        H.mock_fn("neotest-scala.utils", "get_package_name", function(_)
          return "com.example."
        end)

        local namespace_data = {
          type = "namespace",
          name = "MySuite",
          path = "/path/to/MySuite.scala",
        }
        local namespace_tree = mock_tree(namespace_data)

        utest.build_command({
          root_path = "/root",
          project = "myproject",
          tree = namespace_tree,
          name = "MySuite",
          extra_args = {},
        })

        assert.are.equal("com.example.MySuite", test_path_arg)
      end)

      it("returns nil when package is not found", function()
        local test_path_arg = "not_set"
        H.mock_fn("neotest-scala.build", "command_with_path", function(opts)
          test_path_arg = opts.test_path
          return { "sbt", "project/testOnly", opts.test_path }
        end)
        H.mock_fn("neotest-scala.utils", "get_package_name", function(_)
          return nil
        end)

        local namespace_data = {
          type = "namespace",
          name = "MySuite",
          path = "/path/to/MySuite.scala",
        }
        local namespace_tree = mock_tree(namespace_data)

        utest.build_command({
          root_path = "/root",
          project = "myproject",
          tree = namespace_tree,
          name = "MySuite",
          extra_args = {},
        })

        assert.is_nil(test_path_arg)
      end)
    end)
  end)

  describe("build_position_result", function()
    it("maps numeric junit names to ordered discovered tests", function()
      local namespace = {
        tests = {
          {
            id = "com.example.UTestInterpolatedSuite.$baseName-pass",
            type = "test",
            range = { 9, 0, 9, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
          {
            id = "com.example.UTestInterpolatedSuite.$baseName-fail",
            type = "test",
            range = { 14, 0, 14, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
        },
      }

      local first_test = namespace.tests[1]
      local second_test = namespace.tests[2]
      local first_node = mock_tree(first_test)
      local second_node = mock_tree(second_test)

      local junit_results = {
        { namespace = "UTestInterpolatedSuite", name = "0" },
        {
          namespace = "UTestInterpolatedSuite",
          name = "1",
          error_message = "assertion failed",
          error_stacktrace = "java.lang.AssertionError: assertion failed\nat com.example.UTestInterpolatedSuite(UTestInterpolatedSuite.scala:15)",
        },
      }

      local first_result = utest.build_position_result({
        position = first_test,
        test_node = first_node,
        junit_results = junit_results,
        namespace = namespace,
      })
      local second_result = utest.build_position_result({
        position = second_test,
        test_node = second_node,
        junit_results = junit_results,
        namespace = namespace,
      })

      assert.are.equal("passed", first_result.status)
      assert.are.equal("failed", second_result.status)
      assert.are.equal(14, second_result.errors[1].line)
    end)

    it("maps numeric junit names from namespace all_tests for single test runs", function()
      local selected_test = {
        id = "com.example.UTestInterpolatedSuite.$baseName-fail",
        type = "test",
        range = { 14, 0, 14, 0 },
        path = "/path/to/UTestInterpolatedSuite.scala",
      }
      local namespace = {
        tests = { selected_test },
        all_tests = {
          {
            id = "com.example.UTestInterpolatedSuite.$baseName-pass",
            type = "test",
            range = { 9, 0, 9, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
          selected_test,
        },
      }

      local selected_node = mock_tree(selected_test)
      local junit_results = {
        { namespace = "UTestInterpolatedSuite", name = "0" },
        {
          namespace = "UTestInterpolatedSuite",
          name = "1",
          error_message = "assertion failed",
          error_stacktrace = "java.lang.AssertionError: assertion failed\nat com.example.UTestInterpolatedSuite(UTestInterpolatedSuite.scala:15)",
        },
      }

      local selected_result = utest.build_position_result({
        position = selected_test,
        test_node = selected_node,
        junit_results = junit_results,
        namespace = namespace,
      })

      assert.are.equal("failed", selected_result.status)
      assert.are.equal(14, selected_result.errors[1].line)
    end)

    it("maps numeric junit names correctly with interpolated and anonymous tests mixed", function()
      local namespace = {
        tests = {
          {
            id = "com.example.UTestInterpolatedSuite.$baseName-pass",
            type = "test",
            range = { 9, 0, 9, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
          {
            id = "com.example.UTestInterpolatedSuite.test.__anonymous_14_0",
            type = "test",
            range = { 14, 0, 14, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
          {
            id = "com.example.UTestInterpolatedSuite.test.__anonymous_19_0",
            type = "test",
            range = { 19, 0, 19, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
          {
            id = "com.example.UTestInterpolatedSuite.$baseName-crash",
            type = "test",
            range = { 23, 0, 23, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
        },
      }

      local junit_results = {
        { namespace = "UTestInterpolatedSuite", name = "0" },
        {
          namespace = "UTestInterpolatedSuite",
          name = "1",
          error_message = "anonymous fail",
          error_stacktrace = "java.lang.AssertionError: anonymous fail\nat com.example.UTestInterpolatedSuite(UTestInterpolatedSuite.scala:15)",
        },
        {
          namespace = "UTestInterpolatedSuite",
          name = "2",
          error_message = "anonymous crash",
          error_stacktrace = "java.lang.RuntimeException: anonymous crash\nat com.example.UTestInterpolatedSuite(UTestInterpolatedSuite.scala:20)",
        },
        {
          namespace = "UTestInterpolatedSuite",
          name = "3",
          error_message = "interpolated crash",
          error_stacktrace = "java.lang.RuntimeException: interpolated crash\nat com.example.UTestInterpolatedSuite(UTestInterpolatedSuite.scala:24)",
        },
      }

      local pass_result = utest.build_position_result({
        position = namespace.tests[1],
        test_node = mock_tree(namespace.tests[1]),
        junit_results = junit_results,
        namespace = namespace,
      })
      local anon_fail_result = utest.build_position_result({
        position = namespace.tests[2],
        test_node = mock_tree(namespace.tests[2]),
        junit_results = junit_results,
        namespace = namespace,
      })
      local anon_crash_result = utest.build_position_result({
        position = namespace.tests[3],
        test_node = mock_tree(namespace.tests[3]),
        junit_results = junit_results,
        namespace = namespace,
      })
      local crash_result = utest.build_position_result({
        position = namespace.tests[4],
        test_node = mock_tree(namespace.tests[4]),
        junit_results = junit_results,
        namespace = namespace,
      })

      assert.are.equal("passed", pass_result.status)
      assert.are.equal("failed", anon_fail_result.status)
      assert.are.equal(14, anon_fail_result.errors[1].line)
      assert.are.equal("failed", anon_crash_result.status)
      assert.are.equal(19, anon_crash_result.errors[1].line)
      assert.are.equal("failed", crash_result.status)
      assert.are.equal(23, crash_result.errors[1].line)
    end)

    it("maps numeric junit names when anonymous test is second", function()
      local namespace = {
        tests = {
          {
            id = "com.example.UTestInterpolatedSuite.$baseName-pass",
            type = "test",
            range = { 9, 0, 9, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
          {
            id = "com.example.UTestInterpolatedSuite.test.__anonymous_14_0",
            type = "test",
            range = { 14, 0, 14, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
          {
            id = "com.example.UTestInterpolatedSuite.$baseName-fail",
            type = "test",
            range = { 19, 0, 19, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
          {
            id = "com.example.UTestInterpolatedSuite.$baseName-crash",
            type = "test",
            range = { 23, 0, 23, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
        },
      }

      local junit_results = {
        { namespace = "UTestInterpolatedSuite", name = "0" },
        {
          namespace = "UTestInterpolatedSuite",
          name = "1",
          error_message = "anonymous fail",
          error_stacktrace = "java.lang.AssertionError: anonymous fail\nat com.example.UTestInterpolatedSuite(UTestInterpolatedSuite.scala:15)",
        },
        {
          namespace = "UTestInterpolatedSuite",
          name = "2",
          error_message = "interpolated fail",
          error_stacktrace = "java.lang.AssertionError: interpolated fail\nat com.example.UTestInterpolatedSuite(UTestInterpolatedSuite.scala:20)",
        },
        {
          namespace = "UTestInterpolatedSuite",
          name = "3",
          error_message = "interpolated crash",
          error_stacktrace = "java.lang.RuntimeException: interpolated crash\nat com.example.UTestInterpolatedSuite(UTestInterpolatedSuite.scala:24)",
        },
      }

      local pass_result = utest.build_position_result({
        position = namespace.tests[1],
        test_node = mock_tree(namespace.tests[1]),
        junit_results = junit_results,
        namespace = namespace,
      })
      local anon_result = utest.build_position_result({
        position = namespace.tests[2],
        test_node = mock_tree(namespace.tests[2]),
        junit_results = junit_results,
        namespace = namespace,
      })
      local fail_result = utest.build_position_result({
        position = namespace.tests[3],
        test_node = mock_tree(namespace.tests[3]),
        junit_results = junit_results,
        namespace = namespace,
      })
      local crash_result = utest.build_position_result({
        position = namespace.tests[4],
        test_node = mock_tree(namespace.tests[4]),
        junit_results = junit_results,
        namespace = namespace,
      })

      assert.are.equal("passed", pass_result.status)
      assert.are.equal("failed", anon_result.status)
      assert.are.equal(14, anon_result.errors[1].line)
      assert.are.equal("failed", fail_result.status)
      assert.are.equal(19, fail_result.errors[1].line)
      assert.are.equal("failed", crash_result.status)
      assert.are.equal(23, crash_result.errors[1].line)
    end)

    it("prefers discovered position line for numeric interpolated and anonymous junit failures", function()
      local namespace = {
        tests = {
          {
            id = "com.example.UTestInterpolatedSuite.$baseName-pass",
            type = "test",
            name = 's"${baseName}-pass"',
            range = { 9, 0, 9, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
          {
            id = "com.example.UTestInterpolatedSuite.test.__anonymous_14_0",
            type = "test",
            name = "test",
            range = { 14, 0, 14, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
          {
            id = "com.example.UTestInterpolatedSuite.$baseName-fail",
            type = "test",
            name = 's"${baseName}-fail"',
            range = { 19, 0, 19, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
          {
            id = "com.example.UTestInterpolatedSuite.$baseName-crash",
            type = "test",
            name = 's"${baseName}-crash"',
            range = { 23, 0, 23, 0 },
            path = "/path/to/UTestInterpolatedSuite.scala",
          },
        },
      }

      local junit_results = {
        { namespace = "UTestInterpolatedSuite", name = "0" },
        {
          namespace = "UTestInterpolatedSuite",
          name = "1",
          error_message = "anonymous fail",
          error_stacktrace = "java.lang.AssertionError: anonymous fail\nat com.example.UTestInterpolatedSuite(UTestInterpolatedSuite.scala:9)",
        },
        {
          namespace = "UTestInterpolatedSuite",
          name = "2",
          error_message = "interpolated fail",
          error_stacktrace = "java.lang.AssertionError: interpolated fail\nat com.example.UTestInterpolatedSuite(UTestInterpolatedSuite.scala:9)",
        },
        {
          namespace = "UTestInterpolatedSuite",
          name = "3",
          error_message = "interpolated crash",
          error_stacktrace = "java.lang.RuntimeException: interpolated crash\nat com.example.UTestInterpolatedSuite(UTestInterpolatedSuite.scala:31)",
        },
      }

      local anon_result = utest.build_position_result({
        position = namespace.tests[2],
        test_node = mock_tree(namespace.tests[2]),
        junit_results = junit_results,
        namespace = namespace,
      })
      local interpolated_fail_result = utest.build_position_result({
        position = namespace.tests[3],
        test_node = mock_tree(namespace.tests[3]),
        junit_results = junit_results,
        namespace = namespace,
      })
      local interpolated_crash_result = utest.build_position_result({
        position = namespace.tests[4],
        test_node = mock_tree(namespace.tests[4]),
        junit_results = junit_results,
        namespace = namespace,
      })

      assert.are.equal(14, anon_result.errors[1].line)
      assert.are.equal(19, interpolated_fail_result.errors[1].line)
      assert.are.equal(23, interpolated_crash_result.errors[1].line)
    end)
  end)

  describe("parse_stdout_results", function()
    after_each(function()
      H.restore_mocks()
    end)

    it("maps numeric stdout names to ordered discovered tests", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function()
        return "com.example."
      end)

      local namespace = mock_tree({
        id = "UTestInterpolatedSuite",
        type = "namespace",
        name = "UTestInterpolatedSuite",
        path = "/path/to/UTestInterpolatedSuite.scala",
      })

      local test0 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.$baseName-pass",
        type = "test",
        name = 's"${baseName}-pass"',
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 9, 0, 9, 0 },
      }, namespace)
      local test1 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.$baseName-fail",
        type = "test",
        name = 's"${baseName}-fail"',
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 14, 0, 14, 0 },
      }, namespace)
      local test2 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.runtimeName",
        type = "test",
        name = "runtimeName",
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 18, 0, 18, 0 },
      }, namespace)
      namespace._children = { test0, test1, test2 }

      local output = table.concat({
        "+ com.example.UTestInterpolatedSuite.0 4ms",
        "X com.example.UTestInterpolatedSuite.1 0ms",
        "  java.lang.AssertionError: assertion failed: ==> assertion failed: 1 != 2",
        "    com.example.UTestInterpolatedSuite$.$init$$$anonfun$1$$anonfun$2(UTestInterpolatedSuite.scala:15)",
        "X com.example.UTestInterpolatedSuite.2 0ms",
        "  java.lang.RuntimeException: utest interpolated crash",
        "    com.example.UTestInterpolatedSuite$.$init$$$anonfun$1$$anonfun$3(UTestInterpolatedSuite.scala:19)",
      }, "\n")

      local results = utest.parse_stdout_results(output, namespace)

      assert.are.equal("passed", results[test0:data().id].status)
      assert.are.equal("failed", results[test1:data().id].status)
      assert.is_not_nil(results[test1:data().id].errors[1].message:match("AssertionError"))
      assert.are.equal(14, results[test1:data().id].errors[1].line)
      assert.are.equal("failed", results[test2:data().id].status)
      assert.is_not_nil(results[test2:data().id].errors[1].message:match("RuntimeException: utest interpolated crash"))
      assert.are.equal(18, results[test2:data().id].errors[1].line)
    end)

    it("captures exception messages for named utest output", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function()
        return "com.example."
      end)

      local namespace = mock_tree({
        id = "UTestSuite",
        type = "namespace",
        name = "UTestSuite",
        path = "/path/to/UTestSuite.scala",
      })

      local success = mock_tree({
        id = "com.example.UTestSuite.Hello, utest!",
        type = "test",
        name = '"Hello, utest!"',
        path = "/path/to/UTestSuite.scala",
        range = { 8, 0, 8, 0 },
      }, namespace)
      local failing = mock_tree({
        id = "com.example.UTestSuite.failing test",
        type = "test",
        name = '"failing test"',
        path = "/path/to/UTestSuite.scala",
        range = { 12, 0, 12, 0 },
      }, namespace)
      local crashing = mock_tree({
        id = "com.example.UTestSuite.crashing test",
        type = "test",
        name = '"crashing test"',
        path = "/path/to/UTestSuite.scala",
        range = { 16, 0, 16, 0 },
      }, namespace)
      namespace._children = { success, failing, crashing }

      local output = table.concat({
        "+ com.example.UTestSuite.Hello, utest! 7ms",
        "X com.example.UTestSuite.failing test 0ms",
        "  java.lang.AssertionError: assertion failed: ==> assertion failed: 1 != 2",
        "    com.example.UTestSuite$.$init$$$anonfun$1$$anonfun$2(UTestSuite.scala:13)",
        "X com.example.UTestSuite.crashing test 0ms",
        "  java.lang.RuntimeException: Hello world",
        "    com.example.UTestSuite$.$init$$$anonfun$1$$anonfun$3(UTestSuite.scala:17)",
      }, "\n")

      local results = utest.parse_stdout_results(output, namespace)

      assert.are.equal("passed", results[success:data().id].status)
      assert.are.equal("failed", results[failing:data().id].status)
      assert.is_not_nil(results[failing:data().id].errors[1].message:match("AssertionError"))
      assert.are.equal(12, results[failing:data().id].errors[1].line)
      assert.are.equal("failed", results[crashing:data().id].status)
      assert.is_not_nil(results[crashing:data().id].errors[1].message:match("RuntimeException: Hello world"))
      assert.are.equal(16, results[crashing:data().id].errors[1].line)
    end)

    it("maps numeric stdout names with anonymous tests in sequence", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function()
        return "com.example."
      end)

      local namespace = mock_tree({
        id = "UTestInterpolatedSuite",
        type = "namespace",
        name = "UTestInterpolatedSuite",
        path = "/path/to/UTestInterpolatedSuite.scala",
      })

      local test0 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.$baseName-pass",
        type = "test",
        name = 's"${baseName}-pass"',
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 9, 0, 9, 0 },
      }, namespace)
      local test1 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.test.__anonymous_14_0",
        type = "test",
        name = "test",
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 14, 0, 14, 0 },
      }, namespace)
      local test2 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.test.__anonymous_19_0",
        type = "test",
        name = "test",
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 19, 0, 19, 0 },
      }, namespace)
      local test3 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.$baseName-crash",
        type = "test",
        name = 's"${baseName}-crash"',
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 23, 0, 23, 0 },
      }, namespace)
      namespace._children = { test0, test1, test2, test3 }

      local output = table.concat({
        "+ com.example.UTestInterpolatedSuite.0 4ms",
        "X com.example.UTestInterpolatedSuite.1 0ms",
        "  java.lang.AssertionError: anonymous fail",
        "    com.example.UTestInterpolatedSuite$.$init$$$anonfun$1$$anonfun$2(UTestInterpolatedSuite.scala:15)",
        "X com.example.UTestInterpolatedSuite.2 0ms",
        "  java.lang.RuntimeException: anonymous crash",
        "    com.example.UTestInterpolatedSuite$.$init$$$anonfun$1$$anonfun$3(UTestInterpolatedSuite.scala:20)",
        "X com.example.UTestInterpolatedSuite.3 0ms",
        "  java.lang.RuntimeException: utest interpolated crash",
        "    com.example.UTestInterpolatedSuite$.$init$$$anonfun$1$$anonfun$4(UTestInterpolatedSuite.scala:24)",
      }, "\n")

      local results = utest.parse_stdout_results(output, namespace)

      assert.are.equal("passed", results[test0:data().id].status)
      assert.are.equal("failed", results[test1:data().id].status)
      assert.are.equal(14, results[test1:data().id].errors[1].line)
      assert.are.equal("failed", results[test2:data().id].status)
      assert.are.equal(19, results[test2:data().id].errors[1].line)
      assert.are.equal("failed", results[test3:data().id].status)
      assert.are.equal(23, results[test3:data().id].errors[1].line)
    end)

    it("maps numeric stdout names when anonymous test is second", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function()
        return "com.example."
      end)

      local namespace = mock_tree({
        id = "UTestInterpolatedSuite",
        type = "namespace",
        name = "UTestInterpolatedSuite",
        path = "/path/to/UTestInterpolatedSuite.scala",
      })

      local test0 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.$baseName-pass",
        type = "test",
        name = 's"${baseName}-pass"',
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 9, 0, 9, 0 },
      }, namespace)
      local test1 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.test.__anonymous_14_0",
        type = "test",
        name = "test",
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 14, 0, 14, 0 },
      }, namespace)
      local test2 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.$baseName-fail",
        type = "test",
        name = 's"${baseName}-fail"',
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 19, 0, 19, 0 },
      }, namespace)
      local test3 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.$baseName-crash",
        type = "test",
        name = 's"${baseName}-crash"',
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 23, 0, 23, 0 },
      }, namespace)
      namespace._children = { test0, test1, test2, test3 }

      local output = table.concat({
        "+ com.example.UTestInterpolatedSuite.0 4ms",
        "X com.example.UTestInterpolatedSuite.1 0ms",
        "  java.lang.AssertionError: anonymous fail",
        "    com.example.UTestInterpolatedSuite$.$init$$$anonfun$1$$anonfun$2(UTestInterpolatedSuite.scala:15)",
        "X com.example.UTestInterpolatedSuite.2 0ms",
        "  java.lang.AssertionError: interpolated fail",
        "    com.example.UTestInterpolatedSuite$.$init$$$anonfun$1$$anonfun$3(UTestInterpolatedSuite.scala:20)",
        "X com.example.UTestInterpolatedSuite.3 0ms",
        "  java.lang.RuntimeException: interpolated crash",
        "    com.example.UTestInterpolatedSuite$.$init$$$anonfun$1$$anonfun$4(UTestInterpolatedSuite.scala:24)",
      }, "\n")

      local results = utest.parse_stdout_results(output, namespace)

      assert.are.equal("passed", results[test0:data().id].status)
      assert.are.equal("failed", results[test1:data().id].status)
      assert.are.equal(14, results[test1:data().id].errors[1].line)
      assert.are.equal("failed", results[test2:data().id].status)
      assert.are.equal(19, results[test2:data().id].errors[1].line)
      assert.are.equal("failed", results[test3:data().id].status)
      assert.are.equal(23, results[test3:data().id].errors[1].line)
    end)

    it("prefers discovered position line for numeric interpolated and anonymous stdout failures", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function()
        return "com.example."
      end)

      local namespace = mock_tree({
        id = "UTestInterpolatedSuite",
        type = "namespace",
        name = "UTestInterpolatedSuite",
        path = "/path/to/UTestInterpolatedSuite.scala",
      })

      local test0 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.$baseName-pass",
        type = "test",
        name = 's"${baseName}-pass"',
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 9, 0, 9, 0 },
      }, namespace)
      local test1 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.test.__anonymous_14_0",
        type = "test",
        name = "test",
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 14, 0, 14, 0 },
      }, namespace)
      local test2 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.$baseName-fail",
        type = "test",
        name = 's"${baseName}-fail"',
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 19, 0, 19, 0 },
      }, namespace)
      local test3 = mock_tree({
        id = "com.example.UTestInterpolatedSuite.$baseName-crash",
        type = "test",
        name = 's"${baseName}-crash"',
        path = "/path/to/UTestInterpolatedSuite.scala",
        range = { 23, 0, 23, 0 },
      }, namespace)
      namespace._children = { test0, test1, test2, test3 }

      local output = table.concat({
        "+ com.example.UTestInterpolatedSuite.0 4ms",
        "X com.example.UTestInterpolatedSuite.1 0ms",
        "  java.lang.AssertionError: anonymous fail",
        "    com.example.UTestInterpolatedSuite$.$init$$$anonfun$1$$anonfun$2(UTestInterpolatedSuite.scala:9)",
        "X com.example.UTestInterpolatedSuite.2 0ms",
        "  java.lang.AssertionError: interpolated fail",
        "    com.example.UTestInterpolatedSuite$.$init$$$anonfun$1$$anonfun$3(UTestInterpolatedSuite.scala:9)",
        "X com.example.UTestInterpolatedSuite.3 0ms",
        "  java.lang.RuntimeException: interpolated crash",
        "    com.example.UTestInterpolatedSuite$.$init$$$anonfun$1$$anonfun$4(UTestInterpolatedSuite.scala:31)",
      }, "\n")

      local results = utest.parse_stdout_results(output, namespace)

      assert.are.equal(14, results[test1:data().id].errors[1].line)
      assert.are.equal(19, results[test2:data().id].errors[1].line)
      assert.are.equal(23, results[test3:data().id].errors[1].line)
    end)
  end)
end)
