local H = require("tests.helpers")
local strategy = require("neotest-scala.strategy")
local original_notify = vim.notify

local function mock_tree(data)
  return {
    data = function()
      return data
    end,
  }
end

describe("strategy", function()
  after_each(function()
    H.restore_mocks()
    strategy.reset_run_state()
    vim.notify = original_notify
  end)

  describe("get_config", function()
    it("returns nil when strategy is nil", function()
      local tree = mock_tree({
        type = "file",
        path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
      })

      local config = strategy.get_config({
        strategy = nil,
        tree = tree,
        project = "myproject",
        root = "/tmp/project",
      })

      assert.is_nil(config)
    end)

    it("returns nil for integrated strategy", function()
      local tree = mock_tree({
        type = "file",
        path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
      })

      local config = strategy.get_config({
        strategy = "integrated",
        tree = tree,
        project = "myproject",
        root = "/tmp/project",
      })

      assert.is_nil(config)
    end)

    it("builds file-level config for dap file runs", function()
      local tree = mock_tree({
        type = "file",
        path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
      })

      local config = strategy.get_config({
        strategy = "dap",
        tree = tree,
        project = "myproject",
        root = "/tmp/project",
      })

      assert.are.equal("scala", config.type)
      assert.are.equal("launch", config.request)
      assert.are.equal("NeotestScala", config.name)
      assert.are.equal("testFile", config.metals.runType)
      assert.are.equal("/tmp/project/src/test/scala/com/example/MySpec.scala", config.metals.path)
    end)

    it("builds namespace config for dap namespace runs", function()
      H.mock_fn("neotest-scala.utils", "get_package_name", function()
        return "com.example."
      end)

      local tree = mock_tree({
        type = "namespace",
        name = "MySpec",
        path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
      })

      local config = strategy.get_config({
        strategy = "dap",
        tree = tree,
        project = "myproject",
        root = "/tmp/project",
      })

      assert.are.equal("scala", config.type)
      assert.are.equal("launch", config.request)
      assert.are.equal("from_lens", config.name)
      assert.are.equal("com.example.MySpec", config.metals.testClass)
    end)

    it("falls back to file-level config for dap test runs", function()
      local notify_calls = 0
      local notify_messages = {}
      vim.notify = function(message)
        notify_calls = notify_calls + 1
        table.insert(notify_messages, message)
      end

      local tree = mock_tree({
        type = "test",
        path = "/tmp/project/src/test/scala/com/example/MySpec.scala",
        name = '"works"',
      })

      local first_config = strategy.get_config({
        strategy = "dap",
        tree = tree,
        project = "myproject",
        root = "/tmp/project",
      })

      local second_config = strategy.get_config({
        strategy = "dap",
        tree = tree,
        project = "myproject",
        root = "/tmp/project",
      })

      assert.are.equal("testFile", first_config.metals.runType)
      assert.are.equal("/tmp/project/src/test/scala/com/example/MySpec.scala", first_config.metals.path)
      assert.is_nil(first_config.metals.requestData)
      assert.are.equal("testFile", second_config.metals.runType)
      assert.are.equal(1, notify_calls)
      assert.is_true(notify_messages[1]:find("file scope for reliability", 1, true) ~= nil)
    end)
  end)
end)
