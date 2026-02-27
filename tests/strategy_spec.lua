local H = require("tests.helpers")
local strategy = require("neotest-scala.strategy")

local function mk_node(data, parent)
  local node = {
    _data = data,
    _parent = parent,
  }

  function node:data()
    return self._data
  end

  function node:parent()
    return self._parent
  end

  return node
end

describe("strategy", function()
  local original_notify
  local original_schedule
  local original_in_fast_event

  before_each(function()
    H.restore_mocks()
    strategy.reset_run_state()
    original_notify = vim.notify
    original_schedule = vim.schedule
    original_in_fast_event = vim.in_fast_event
  end)

  after_each(function()
    H.restore_mocks()
    strategy.reset_run_state()
    vim.notify = original_notify
    vim.schedule = original_schedule
    vim.in_fast_event = original_in_fast_event
  end)

  it("returns nil when strategy is nil", function()
    local tree = mk_node({
      type = "file",
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    })

    local config = strategy.get_config({
      strategy = nil,
      tree = tree,
      project = "root",
      root = "/tmp/project",
      framework = "munit",
    })

    assert.is_nil(config)
  end)

  it("returns nil for integrated strategy", function()
    local tree = mk_node({
      type = "file",
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    })

    local config = strategy.get_config({
      strategy = "integrated",
      tree = tree,
      project = "root",
      root = "/tmp/project",
      framework = "munit",
    })

    assert.is_nil(config)
  end)

  it("builds file-level config for dap file runs", function()
    local tree = mk_node({
      type = "file",
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    })

    local config = strategy.get_config({
      strategy = "dap",
      tree = tree,
      project = "root",
      root = "/tmp/project",
      framework = "munit",
    })

    assert.are.equal("scala", config.type)
    assert.are.equal("launch", config.request)
    assert.are.equal("testFile", config.metals.runType)
    assert.are.equal(vim.uri_from_fname("/tmp/project/src/test/scala/com/example/MySpec.scala"), config.metals.path)
  end)

  it("builds namespace config for dap namespace runs", function()
    H.mock_fn("neotest-scala.utils", "get_package_name", function()
      return "com.example."
    end)

    local tree = mk_node({
      type = "namespace",
      name = "MySpec",
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    })

    local config = strategy.get_config({
      strategy = "dap",
      tree = tree,
      project = "root",
      root = "/tmp/project",
      framework = "munit",
    })

    assert.are.equal("scala", config.type)
    assert.are.equal("launch", config.request)
    assert.are.equal("com.example.MySpec", config.metals.testClass)
  end)

  it("builds test selector payload for eligible literal tests", function()
    H.mock_fn("neotest-scala.framework", "supports_dap_test_selector", function()
      return true
    end)
    H.mock_fn("neotest-scala.framework", "get_framework_class", function()
      return {
        build_dap_test_selector = function()
          return "works selector"
        end,
      }
    end)
    H.mock_fn("neotest-scala.utils", "get_package_name", function()
      return "com.example."
    end)

    local namespace_node = mk_node({
      type = "namespace",
      name = "MySpec",
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    })
    local test_node = mk_node({
      type = "test",
      name = '"works"',
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    }, namespace_node)

    local config = strategy.get_config({
      strategy = "dap",
      tree = test_node,
      project = "root",
      root = "/tmp/project",
      framework = "munit",
    })

    assert.are.equal("from_lens", config.name)
    assert.are.equal("file:/tmp/project/?id=root-test", config.metals.target.uri)
    assert.are.equal("com.example.MySpec", config.metals.requestData.suites[1].className)
    assert.are.equal("works selector", config.metals.requestData.suites[1].tests[1])
  end)

  it("maps nested clicked test to top-level test selector", function()
    local captured_position_name = nil

    H.mock_fn("neotest-scala.framework", "supports_dap_test_selector", function()
      return true
    end)
    H.mock_fn("neotest-scala.framework", "get_framework_class", function()
      return {
        build_dap_test_selector = function(opts)
          captured_position_name = opts.position.name
          return "resolved selector"
        end,
      }
    end)
    H.mock_fn("neotest-scala.utils", "get_package_name", function()
      return "com.example."
    end)

    local namespace_node = mk_node({
      type = "namespace",
      name = "MySpec",
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    })
    local parent_test = mk_node({
      type = "test",
      name = '"top level test"',
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    }, namespace_node)
    local nested_test = mk_node({
      type = "test",
      name = '"nested test"',
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    }, parent_test)

    local config = strategy.get_config({
      strategy = "dap",
      tree = nested_test,
      project = "root",
      root = "/tmp/project",
      framework = "scalatest",
    })

    assert.are.equal('"top level test"', captured_position_name)
    assert.are.equal("resolved selector", config.metals.requestData.suites[1].tests[1])
  end)

  it("falls back to file-level debug for interpolated names and notifies once per run", function()
    local notify_count = 0
    vim.notify = function()
      notify_count = notify_count + 1
    end

    H.mock_fn("neotest-scala.framework", "supports_dap_test_selector", function()
      return true
    end)
    H.mock_fn("neotest-scala.framework", "get_framework_class", function()
      return {
        build_dap_test_selector = function()
          return "selector"
        end,
      }
    end)

    local namespace_node = mk_node({
      type = "namespace",
      name = "MySpec",
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    })
    local test_node = mk_node({
      type = "test",
      name = 's"$baseName works"',
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    }, namespace_node)

    local first = strategy.get_config({
      strategy = "dap",
      tree = test_node,
      project = "root",
      root = "/tmp/project",
      framework = "munit",
    })

    local second = strategy.get_config({
      strategy = "dap",
      tree = test_node,
      project = "root",
      root = "/tmp/project",
      framework = "munit",
    })

    assert.are.equal("testFile", first.metals.runType)
    assert.are.equal("testFile", second.metals.runType)
    assert.is_nil(first.metals.requestData)
    assert.are.equal(1, notify_count)
  end)

  it("falls back to file-level debug for unsupported frameworks", function()
    local notify_count = 0
    vim.notify = function()
      notify_count = notify_count + 1
    end

    H.mock_fn("neotest-scala.framework", "supports_dap_test_selector", function()
      return false
    end)

    local namespace_node = mk_node({
      type = "namespace",
      name = "MySpec",
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    })
    local test_node = mk_node({
      type = "test",
      name = '"works"',
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    }, namespace_node)

    local config = strategy.get_config({
      strategy = "dap",
      tree = test_node,
      project = "root",
      root = "/tmp/project",
      framework = "utest",
    })

    assert.are.equal("testFile", config.metals.runType)
    assert.are.equal(1, notify_count)
  end)

  it("resets fallback notification between runs", function()
    local notify_count = 0
    vim.notify = function()
      notify_count = notify_count + 1
    end

    H.mock_fn("neotest-scala.framework", "supports_dap_test_selector", function()
      return false
    end)

    local namespace_node = mk_node({
      type = "namespace",
      name = "MySpec",
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    })
    local test_node = mk_node({
      type = "test",
      name = '"works"',
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    }, namespace_node)

    strategy.get_config({
      strategy = "dap",
      tree = test_node,
      project = "root",
      root = "/tmp/project",
      framework = "utest",
    })

    strategy.reset_run_state()

    strategy.get_config({
      strategy = "dap",
      tree = test_node,
      project = "root",
      root = "/tmp/project",
      framework = "utest",
    })

    assert.are.equal(2, notify_count)
  end)

  it("schedules fallback notification in fast event context", function()
    local notify_called = false
    local scheduled = false
    vim.notify = function()
      notify_called = true
    end
    vim.schedule = function(cb)
      scheduled = true
      cb()
    end
    vim.in_fast_event = function()
      return true
    end

    H.mock_fn("neotest-scala.framework", "supports_dap_test_selector", function()
      return false
    end)

    local namespace_node = mk_node({
      type = "namespace",
      name = "MySpec",
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    })
    local test_node = mk_node({
      type = "test",
      name = '"works"',
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    }, namespace_node)

    strategy.get_config({
      strategy = "dap",
      tree = test_node,
      project = "root",
      root = "/tmp/project",
      framework = "utest",
    })

    assert.is_true(scheduled)
    assert.is_true(notify_called)
  end)
end)
