local H = require("tests.helpers")

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
    parse_positions_calls = {}
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
    H.mock_fn("neotest-scala.build", "command_with_path", function(opts)
      captured_test_path = opts.test_path
      return { "sbt", opts.project .. "/testOnly", opts.test_path }
    end)
  end)

  after_each(function()
    H.restore_mocks()
  end)

  describe("discover_positions", function()
    it("discovers tests for munit FunSuite", function()
      local tree = munit.discover_positions({
        path = "/project/src/test/scala/com/example/FunSuite.scala",
        content = [[
          class FunSuiteSpec extends FunSuite {
            test("works") { assert(1 == 1) }
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.are.equal(1, #parse_positions_calls)
    end)

    it("discovers tests for CatsEffectSuite", function()
      local tree = munit.discover_positions({
        path = "/project/src/test/scala/com/example/CatsEffectSuite.scala",
        content = [[
          class CatsEffectSpec extends CatsEffectSuite {
            test("works") { ??? }
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.is_true(parse_positions_calls[1].query:find('"test"', 1, true) ~= nil)
    end)

    it("discovers property tests for ScalaCheckSuite", function()
      local tree = munit.discover_positions({
        path = "/project/src/test/scala/com/example/ScalaCheckSuite.scala",
        content = [[
          class ScalaCheckSpec extends ScalaCheckSuite {
            property("commutative") { ??? }
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.is_true(parse_positions_calls[1].query:find('"property"', 1, true) ~= nil)
    end)

    it("discovers tests for DisciplineSuite", function()
      local tree = munit.discover_positions({
        path = "/project/src/test/scala/com/example/DisciplineSuite.scala",
        content = [[
          class DisciplineSpec extends DisciplineSuite {
            test("works") { assert(true) }
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.are.equal(1, #parse_positions_calls)
    end)

    it("discovers testZ tests for ZIOSuite", function()
      local tree = munit.discover_positions({
        path = "/project/src/test/scala/com/example/ZioSuite.scala",
        content = [[
          class ZioSpec extends ZIOSuite {
            testZ("zio test") { ??? }
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.is_true(parse_positions_calls[1].query:find('"testZ"', 1, true) ~= nil)
    end)

    it("supports interpolated string names in testZ", function()
      local tree = munit.discover_positions({
        path = "/project/src/test/scala/com/example/ZioSuite.scala",
        content = [[
          class ZioSpec extends ZIOSuite {
            val baseName = "zio"
            testZ(s"$baseName success2") { ??? }
          }
        ]],
      })

      assert.is_not_nil(tree)
      assert.is_true(parse_positions_calls[1].query:find("interpolated_string_expression", 1, true) ~= nil)
    end)

    it("returns nil for unsupported style", function()
      local tree = munit.discover_positions({
        path = "/project/src/test/scala/com/example/Nope.scala",
        content = [[
          class NoopSpec extends AnyFlatSpec {
            "x" should "y" in {}
          }
        ]],
      })

      assert.is_nil(tree)
      assert.are.equal(0, #parse_positions_calls)
    end)
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

        munit.build_command({
          root_path = "/project",
          project = "root",
          tree = test_tree,
          name = "should pass",
          extra_args = {},
        })

        assert.are.equal("com.example.MySpec.should pass", captured_test_path)
      end)

      it("uses suite path for bloop single-test runs", function()
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

        munit.build_command({
          root_path = "/project",
          project = "root",
          tree = test_tree,
          name = "should pass",
          extra_args = {},
          build_tool = "bloop",
        })

        assert.are.equal("com.example.MySpec", captured_test_path)
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

        munit.build_command({
          root_path = "/project",
          project = "root",
          tree = nested_test_tree,
          name = "child test",
          extra_args = {},
        })

        assert.are.equal("com.example.NestedSpec.parent test.child test", captured_test_path)
      end)
    end)

    describe("for namespace (type == 'namespace')", function()
      it("builds path with package and spec name", function()
        local namespace_tree = mock_tree({
          type = "namespace",
          name = "MySpec",
          path = "/project/src/test/scala/com/example/MySpec.scala",
        })

        munit.build_command({
          root_path = "/project",
          project = "root",
          tree = namespace_tree,
          name = "MySpec",
          extra_args = {},
        })

        assert.are.equal("com.example.MySpec", captured_test_path)
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

        munit.build_command({
          root_path = "/project",
          project = "root",
          tree = namespace_tree,
          name = "NoPackageSpec",
          extra_args = {},
        })

        assert.is_nil(captured_test_path)
      end)
    end)

    describe("for file (type == 'file')", function()
      it("builds path with package and suite when file has one suite", function()
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

        munit.build_command({
          root_path = "/project",
          project = "root",
          tree = file_tree,
          name = "FileSpec.scala",
          extra_args = {},
        })

        assert.are.equal("com.example.FileSpec", captured_test_path)
      end)

      it("builds package wildcard when file has multiple suites", function()
        local namespace_child1 = mock_tree({
          type = "namespace",
          name = "SuiteA",
          path = "/project/src/test/scala/com/example/MultiSpec.scala",
        })
        local namespace_child2 = mock_tree({
          type = "namespace",
          name = "SuiteB",
          path = "/project/src/test/scala/com/example/MultiSpec.scala",
        })

        local file_tree = mock_tree({
          type = "file",
          name = "MultiSpec.scala",
          path = "/project/src/test/scala/com/example/MultiSpec.scala",
        }, nil, { namespace_child1, namespace_child2 })

        munit.build_command({
          root_path = "/project",
          project = "root",
          tree = file_tree,
          name = "MultiSpec.scala",
          extra_args = {},
        })

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

        munit.build_command({
          root_path = "/project",
          project = "root",
          tree = dir_tree,
          name = "scala",
          extra_args = {},
        })

        assert.are.equal("*", captured_test_path)
      end)
    end)
  end)

  describe("build_dap_test_selector", function()
    it("builds selector for top-level test", function()
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

      local selector = munit.build_dap_test_selector({
        tree = test_tree,
        position = test_tree:data(),
      })

      assert.are.equal("com.example.MySpec.should pass", selector)
    end)

    it("builds selector for nested tests", function()
      local namespace_tree = mock_tree({
        type = "namespace",
        name = "NestedSpec",
        path = "/project/src/test/scala/com/example/NestedSpec.scala",
      })

      local parent_test = mock_tree({
        type = "test",
        name = '"parent test"',
        path = "/project/src/test/scala/com/example/NestedSpec.scala",
      }, namespace_tree)

      local nested_test = mock_tree({
        type = "test",
        name = '"child test"',
        path = "/project/src/test/scala/com/example/NestedSpec.scala",
      }, parent_test)

      local selector = munit.build_dap_test_selector({
        tree = nested_test,
        position = nested_test:data(),
      })

      assert.are.equal("com.example.NestedSpec.parent test.child test", selector)
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

      it("matches interpolated discovered names to resolved junit names", function()
        local junit_test = {
          namespace = "ZioMUnitSuite",
          name = "zio success2",
        }
        local position = {
          id = "com.example.ZioMUnitSuite.$baseNamesuccess2",
          name = 's"$baseName success2"',
          path = "/project/src/test/scala/com/example/ZioMUnitSuite.scala",
        }

        local result = munit.build_test_result(junit_test, position)

        assert.is_not_nil(result)
        assert.are.equal(fw.TEST_PASSED, result.status)
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

      it("removes source snippet lines from error message", function()
        local junit_test = {
          error_stacktrace = [[
munit.ComparisonFailException: /tmp/DisciplineMUnitSuite.scala:12 assertion failed
11:  test("discipline style failure") {
12:    assertEquals(List(1, 2).size, 99)
13:  }
Values are not the same
]],
        }
        local position = {
          path = "/project/src/test/scala/com/example/DisciplineMUnitSuite.scala",
        }

        local result = munit.build_test_result(junit_test, position)

        assert.is_not_nil(result.errors[1].message)
        assert.is_nil(result.errors[1].message:match("^11:", 1, true))
        assert.is_nil(result.errors[1].message:match("12:%s+assertEquals", 1, false))
        assert.is_not_nil(result.errors[1].message:match("Values are not the same", 1, true))
      end)

      it("extracts line from snippet when stacktrace has no file reference", function()
        local junit_test = {
          error_stacktrace = [[
munit.ComparisonFailException: assertion failed
11:  test("discipline style failure") {
12:    assertEquals(List(1, 2).size, 99)
13:  }
values are not the same
]],
        }
        local position = {
          path = "/project/src/test/scala/com/example/DisciplineMUnitSuite.scala",
        }

        local result = munit.build_test_result(junit_test, position)

        assert.are.equal(11, result.errors[1].line)
        assert.is_not_nil(result.errors[1].message:match("values are not the same", 1, true))
      end)
    end)
  end)

  describe("parse_stdout_results", function()
    it("captures ScalaCheck seed failures and line numbers", function()
      local namespace_tree = mock_tree({
        type = "namespace",
        name = "ScalaCheckMUnitSuite",
        path = "/project/src/test/scala/com/example/ScalaCheckMUnitSuite.scala",
      })

      local pass_tree = mock_tree({
        id = "com.example.ScalaCheckMUnitSuite.reverse reverse is identity",
        type = "test",
        name = '"reverse reverse is identity"',
        path = "/project/src/test/scala/com/example/ScalaCheckMUnitSuite.scala",
      }, namespace_tree)
      local fail_tree = mock_tree({
        id = "com.example.ScalaCheckMUnitSuite.intentionally failing property",
        type = "test",
        name = '"intentionally failing property"',
        path = "/project/src/test/scala/com/example/ScalaCheckMUnitSuite.scala",
      }, namespace_tree)

      local root = mock_tree({
        type = "file",
        path = "/project/src/test/scala/com/example/ScalaCheckMUnitSuite.scala",
      }, nil, { pass_tree, fail_tree })
      namespace_tree._parent = root

      local output = [[
+ com.example.ScalaCheckMUnitSuite.reverse reverse is identity 0.02s
==> X com.example.ScalaCheckMUnitSuite.intentionally failing property 0.01s
munit.FailException: /tmp/ScalaCheckMUnitSuite.scala:17
16:    }
17:  }
18:
Failing seed: Xq5QcHcxgqqNkBJvwuEN99CKcoc9_q9Lxlwq992-h0D=
You can reproduce this failure by adding the following override to your suite:
at com.example.ScalaCheckMUnitSuite.$anonfun$2(ScalaCheckMUnitSuite.scala:14)
]]

      local results = munit.parse_stdout_results(output, root)
      local diagnostic = results["com.example.ScalaCheckMUnitSuite.intentionally failing property"].errors[1].message

      assert.are.equal(fw.TEST_PASSED, results["com.example.ScalaCheckMUnitSuite.reverse reverse is identity"].status)
      assert.are.equal(fw.TEST_FAILED, results["com.example.ScalaCheckMUnitSuite.intentionally failing property"].status)
      assert.are.equal(16, results["com.example.ScalaCheckMUnitSuite.intentionally failing property"].errors[1].line)
      assert.is_not_nil(diagnostic:match("Failing seed:"))
      assert.is_nil(diagnostic:match("^18:%s*$"))
    end)

    it("strips source snippet from bloop diagnostics", function()
      local namespace_tree = mock_tree({
        type = "namespace",
        name = "DisciplineMUnitSuite",
        path = "/project/src/test/scala/com/example/DisciplineMUnitSuite.scala",
      })

      local fail_tree = mock_tree({
        id = "com.example.DisciplineMUnitSuite.discipline style failure",
        type = "test",
        name = '"discipline style failure"',
        path = "/project/src/test/scala/com/example/DisciplineMUnitSuite.scala",
      }, namespace_tree)

      local root = mock_tree({
        type = "file",
        path = "/project/src/test/scala/com/example/DisciplineMUnitSuite.scala",
      }, nil, { fail_tree })
      namespace_tree._parent = root

      local output = [[
==> X com.example.DisciplineMUnitSuite.discipline style failure 0.01s
munit.ComparisonFailException: /tmp/DisciplineMUnitSuite.scala:12 assertion failed
11:  test("discipline style failure") {
12:    assertEquals(List(1, 2).size, 99)
13:  }
Values are not the same
]]

      local results = munit.parse_stdout_results(output, root)
      local diagnostic = results["com.example.DisciplineMUnitSuite.discipline style failure"].errors[1].message

      assert.are.equal(fw.TEST_FAILED, results["com.example.DisciplineMUnitSuite.discipline style failure"].status)
      assert.are.equal(11, results["com.example.DisciplineMUnitSuite.discipline style failure"].errors[1].line)
      assert.is_nil(diagnostic:match("^11:", 1, true))
      assert.is_nil(diagnostic:match("12:%s+assertEquals", 1, false))
      assert.is_not_nil(diagnostic:match("Values are not the same", 1, true))
    end)

    it("does not include suite summary in crash diagnostics", function()
      local namespace_tree = mock_tree({
        type = "namespace",
        name = "DisciplineMUnitSuite",
        path = "/project/src/test/scala/com/example/DisciplineMUnitSuite.scala",
      })

      local style_failure_tree = mock_tree({
        id = "com.example.DisciplineMUnitSuite.discipline style failure",
        type = "test",
        name = '"discipline style failure"',
        path = "/project/src/test/scala/com/example/DisciplineMUnitSuite.scala",
      }, namespace_tree)
      local crash_tree = mock_tree({
        id = "com.example.DisciplineMUnitSuite.discipline crash",
        type = "test",
        name = '"discipline crash"',
        path = "/project/src/test/scala/com/example/DisciplineMUnitSuite.scala",
      }, namespace_tree)

      local root = mock_tree({
        type = "file",
        path = "/project/src/test/scala/com/example/DisciplineMUnitSuite.scala",
      }, nil, { style_failure_tree, crash_tree })
      namespace_tree._parent = root

      local output = [[
==> X com.example.DisciplineMUnitSuite.discipline style failure 0.01s
munit.ComparisonFailException: /tmp/DisciplineMUnitSuite.scala:12 assertion failed
values are not the same
==> X com.example.DisciplineMUnitSuite.discipline crash 0.01s
java.lang.IllegalStateException: discipline suite crash
at com.example.DisciplineMUnitSuite.$init$$$anonfun$4(DisciplineMUnitSuite.scala:22)
Execution took 79ms
4 tests, 2 passed, 2 failed
The test execution was successfully closed.
================================================================================
Total duration: 79ms
1 failed
Failed:
- com.example.DisciplineMUnitSuite:
* com.example.DisciplineMUnitSuite.discipline style failure - values are not the same
* com.example.DisciplineMUnitSuite.discipline crash - java.lang.IllegalStateException: discipline suite crash
================================================================================
]]

      local results = munit.parse_stdout_results(output, root)
      local diagnostic = results["com.example.DisciplineMUnitSuite.discipline crash"].errors[1].message

      assert.are.equal(fw.TEST_FAILED, results["com.example.DisciplineMUnitSuite.discipline crash"].status)
      assert.are.equal(21, results["com.example.DisciplineMUnitSuite.discipline crash"].errors[1].line)
      assert.is_not_nil(diagnostic:match("IllegalStateException: discipline suite crash", 1, true))
      assert.is_nil(diagnostic:match("Execution took", 1, true))
      assert.is_nil(diagnostic:match("The test execution was successfully closed", 1, true))
      assert.is_nil(diagnostic:match("discipline style failure", 1, true))
    end)

    it("uses snippet line when no stack frame line is present", function()
      local namespace_tree = mock_tree({
        type = "namespace",
        name = "DisciplineMUnitSuite",
        path = "/project/src/test/scala/com/example/DisciplineMUnitSuite.scala",
      })

      local fail_tree = mock_tree({
        id = "com.example.DisciplineMUnitSuite.discipline style failure",
        type = "test",
        name = '"discipline style failure"',
        path = "/project/src/test/scala/com/example/DisciplineMUnitSuite.scala",
      }, namespace_tree)

      local root = mock_tree({
        type = "file",
        path = "/project/src/test/scala/com/example/DisciplineMUnitSuite.scala",
      }, nil, { fail_tree })
      namespace_tree._parent = root

      local output = [[
==> X com.example.DisciplineMUnitSuite.discipline style failure 0.01s
munit.ComparisonFailException: assertion failed
11:  test("discipline style failure") {
12:    assertEquals(List(1, 2).size, 99)
13:  }
values are not the same
]]

      local results = munit.parse_stdout_results(output, root)
      local result = results["com.example.DisciplineMUnitSuite.discipline style failure"]

      assert.are.equal(fw.TEST_FAILED, result.status)
      assert.are.equal(11, result.errors[1].line)
      assert.is_not_nil(result.errors[1].message:match("values are not the same", 1, true))
    end)

    it("marks all positions failed when bloop reports no suites were run", function()
      local namespace_tree = mock_tree({
        type = "namespace",
        name = "CatsEffectMUnitSuite",
        path = "/project/src/test/scala/com/example/CatsEffectMUnitSuite.scala",
      })

      local test_tree = mock_tree({
        id = "com.example.CatsEffectMUnitSuite.cats effect success",
        type = "test",
        name = '"cats effect success"',
        path = "/project/src/test/scala/com/example/CatsEffectMUnitSuite.scala",
      }, namespace_tree)

      local root = mock_tree({
        type = "file",
        path = "/project/src/test/scala/com/example/CatsEffectMUnitSuite.scala",
      }, nil, { test_tree })
      namespace_tree._parent = root

      local output = [[
The test execution was successfully closed.
================================================================================
Total duration: 0ms
No test suites were run.
================================================================================
]]

      local results = munit.parse_stdout_results(output, root)
      local result = results["com.example.CatsEffectMUnitSuite.cats effect success"]

      assert.are.equal(fw.TEST_FAILED, result.status)
      assert.are.equal("No test suites were run", result.errors[1].message)
    end)
  end)
end)
