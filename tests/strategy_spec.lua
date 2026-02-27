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
  before_each(function()
    H.restore_mocks()
  end)

  after_each(function()
    H.restore_mocks()
  end)

  it("returns nil when strategy is nil", function()
    local tree = mk_node({
      type = "file",
      path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
    })

    local config = strategy.get_config({
      strategy = nil,
      tree = tree,
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
    })

    assert.are.equal("scala", config.type)
    assert.are.equal("launch", config.request)
    assert.are.equal("com.example.MySpec", config.metals.testClass)
  end)

  it("uses file-level debug for dap test runs", function()
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
    })

    assert.are.equal("testFile", config.metals.runType)
    assert.is_nil(config.metals.requestData)
  end)
end)
