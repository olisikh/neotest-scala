local H = require("tests.helpers")

package.loaded["neotest-scala.junit"] = {
  collect_results = function()
    return {}
  end,
}

describe("build tool switch behavior", function()
  before_each(function()
    H.restore_mocks()
  end)

  after_each(function()
    H.restore_mocks()
  end)

  describe("results collect", function()
    it("uses pinned build tool from spec env when available", function()
      local results = require("neotest-scala.results")

      local parse_called = false

      H.mock_fn("neotest.lib", "files", {
        read = function()
          return "test output"
        end,
      })

      H.mock_fn("neotest-scala.framework", "get_framework_class", function()
        return {
          name = "munit",
          parse_stdout_results = function()
            parse_called = true
            return { ["test.id"] = { status = TEST_PASSED } }
          end,
        }
      end)

      H.mock_fn("neotest-scala.build", "get_tool", function()
        return "sbt"
      end)

      local spec = {
        env = {
          framework = "munit",
          root_path = "/tmp/project",
          build_tool = "bloop",
        },
      }

      local collected = results.collect(spec, { output = "/tmp/out.log" }, {})

      assert.is_true(parse_called)
      assert.are.same({ ["test.id"] = { status = TEST_PASSED } }, collected)
    end)

    it("falls back to dynamic tool lookup when pinned tool is missing", function()
      local results = require("neotest-scala.results")

      local parse_called = false

      H.mock_fn("neotest.lib", "files", {
        read = function()
          return "test output"
        end,
      })

      H.mock_fn("neotest-scala.framework", "get_framework_class", function()
        return {
          name = "munit",
          parse_stdout_results = function()
            parse_called = true
            return { ["fallback.id"] = { status = TEST_PASSED } }
          end,
        }
      end)

      H.mock_fn("neotest-scala.build", "get_tool", function()
        return "bloop"
      end)

      local spec = {
        env = {
          framework = "munit",
          root_path = "/tmp/project",
        },
      }

      local collected = results.collect(spec, { output = "/tmp/out.log" }, {})

      assert.is_true(parse_called)
      assert.are.same({ ["fallback.id"] = { status = TEST_PASSED } }, collected)
    end)
  end)

  describe("adapter build_spec", function()
    it("pins resolved build tool into env and forwards it to framework command", function()
      local adapter = require("neotest-scala")

      local captured_tool
      local captured_build_info

      H.mock_fn("neotest-scala.metals", "get_build_target_info", function()
        return {
          ["Target"] = { "munit-test" },
          ["Base Directory"] = { "file:/tmp/project/" },
        }
      end)

      H.mock_fn("neotest-scala.metals", "get_project_name", function()
        return "munit"
      end)

      H.mock_fn("neotest-scala.metals", "get_framework", function()
        return "munit"
      end)

      H.mock_fn("neotest-scala.build", "get_tool", function(_, build_target_info)
        captured_build_info = build_target_info
        return "bloop"
      end)

      H.mock_fn("neotest-scala.framework", "get_framework_class", function()
        return {
          build_command = function(opts)
            captured_tool = opts.build_tool
            return { "echo", "ok" }
          end,
        }
      end)

      H.mock_fn("neotest-scala.strategy", "get_config", function()
        return { strategy = "integrated" }
      end)

      adapter({ cache_build_info = false })

      local spec = adapter.build_spec({
        tree = {
          data = function()
            return {
              type = "test",
              path = "/tmp/project/src/test/scala/ExampleSpec.scala",
              name = "\"works\"",
            }
          end,
        },
        extra_args = {},
      })

      assert.are.equal("bloop", captured_tool)
      assert.are.equal("bloop", spec.env.build_tool)
      assert.are.same({ "munit-test" }, captured_build_info["Target"])
      assert.are.same({ "echo", "ok" }, spec.command)
    end)

    it("refreshes build target info in auto mode to pick up tool switches", function()
      local adapter = require("neotest-scala")

      local captured_build_info
      local call_idx = 0

      H.mock_fn("neotest-scala.metals", "get_build_target_info", function(_)
        call_idx = call_idx + 1
        if call_idx == 1 then
          return {
            ["Target"] = { "munit-test" },
            ["Build server"] = { "sbt" },
            ["Base Directory"] = { "file:/tmp/project/" },
          }
        end

        return {
          ["Target"] = { "munit-test" },
          ["Build server"] = { "bloop" },
          ["Base Directory"] = { "file:/tmp/project/" },
        }
      end)

      H.mock_fn("neotest-scala.metals", "get_project_name", function()
        return "munit"
      end)

      H.mock_fn("neotest-scala.metals", "get_framework", function()
        return "munit"
      end)

      H.mock_fn("neotest-scala.build", "is_auto_mode", function()
        return true
      end)

      H.mock_fn("neotest-scala.build", "get_tool", function(_, build_target_info)
        captured_build_info = build_target_info
        return "bloop"
      end)

      H.mock_fn("neotest-scala.framework", "get_framework_class", function()
        return {
          build_command = function()
            return { "echo", "ok" }
          end,
        }
      end)

      H.mock_fn("neotest-scala.strategy", "get_config", function()
        return { strategy = "integrated" }
      end)

      adapter({ cache_build_info = true })

      adapter.build_spec({
        tree = {
          data = function()
            return {
              type = "test",
              path = "/tmp/project/src/test/scala/ExampleSpec.scala",
              name = "\"works\"",
            }
          end,
        },
        extra_args = {},
      })

      assert.are.equal(2, call_idx)
      assert.are.same({ "bloop" }, captured_build_info["Build server"])
    end)

    it("forces sbt when framework does not support bloop", function()
      local adapter = require("neotest-scala")

      local captured_tool

      H.mock_fn("neotest-scala.metals", "get_build_target_info", function()
        return {
          ["Target"] = { "utest-test" },
          ["Base Directory"] = { "file:/tmp/project/" },
        }
      end)

      H.mock_fn("neotest-scala.metals", "get_project_name", function()
        return "utest"
      end)

      H.mock_fn("neotest-scala.metals", "get_framework", function()
        return "utest"
      end)

      H.mock_fn("neotest-scala.build", "get_tool", function()
        return "bloop"
      end)

      H.mock_fn("neotest-scala.framework", "get_framework_class", function()
        return {
          build_command = function(opts)
            captured_tool = opts.build_tool
            return { "echo", "ok" }
          end,
        }
      end)

      H.mock_fn("neotest-scala.strategy", "get_config", function()
        return { strategy = "integrated" }
      end)

      adapter({ cache_build_info = false })

      local spec = adapter.build_spec({
        tree = {
          data = function()
            return {
              type = "test",
              path = "/tmp/project/src/test/scala/ExampleSpec.scala",
              name = "\"works\"",
            }
          end,
        },
        extra_args = {},
      })

      assert.are.equal("sbt", captured_tool)
      assert.are.equal("sbt", spec.env.build_tool)
    end)

    it("forces sbt for zio-test when detected tool is bloop", function()
      local adapter = require("neotest-scala")

      local captured_tool

      H.mock_fn("neotest-scala.metals", "get_build_target_info", function()
        return {
          ["Target"] = { "zio-test-test" },
          ["Base Directory"] = { "file:/tmp/project/" },
        }
      end)

      H.mock_fn("neotest-scala.metals", "get_project_name", function()
        return "zio-test"
      end)

      H.mock_fn("neotest-scala.metals", "get_framework", function()
        return "zio-test"
      end)

      H.mock_fn("neotest-scala.build", "get_tool", function()
        return "bloop"
      end)

      H.mock_fn("neotest-scala.framework", "get_framework_class", function()
        return {
          build_command = function(opts)
            captured_tool = opts.build_tool
            return { "echo", "ok" }
          end,
        }
      end)

      H.mock_fn("neotest-scala.strategy", "get_config", function()
        return { strategy = "integrated" }
      end)

      adapter({ cache_build_info = false })

      local spec = adapter.build_spec({
        tree = {
          data = function()
            return {
              type = "test",
              path = "/tmp/project/src/test/scala/ZioSpec.scala",
              name = "\"works\"",
            }
          end,
        },
        extra_args = {},
      })

      assert.are.equal("sbt", captured_tool)
      assert.are.equal("sbt", spec.env.build_tool)
    end)

    it("uses file-level dap strategy when debugging nearest test", function()
      local adapter = require("neotest-scala")

      H.mock_fn("neotest-scala.metals", "get_build_target_info", function()
        return {
          ["Target"] = { "munit-test" },
          ["Base Directory"] = { "file:/tmp/project/" },
        }
      end)

      H.mock_fn("neotest-scala.metals", "get_project_name", function()
        return "munit"
      end)

      H.mock_fn("neotest-scala.metals", "get_framework", function()
        return "munit"
      end)

      H.mock_fn("neotest-scala.build", "get_tool", function()
        return "sbt"
      end)

      H.mock_fn("neotest-scala.framework", "get_framework_class", function()
        return {
          build_command = function()
            return { "echo", "ok" }
          end,
        }
      end)

      adapter({ cache_build_info = false })

      local spec = adapter.build_spec({
        tree = {
          data = function()
            return {
              type = "test",
              path = "/tmp/project/src/test/scala/ExampleSpec.scala",
              name = "\"works\"",
            }
          end,
        },
        strategy = "dap",
        extra_args = {},
      })

      assert.are.equal("scala", spec.strategy.type)
      assert.are.equal("testFile", spec.strategy.metals.runType)
      assert.are.equal(vim.uri_from_fname("/tmp/project/src/test/scala/ExampleSpec.scala"), spec.strategy.metals.path)
      assert.is_nil(spec.strategy.metals.requestData)
    end)

    it("does not attach debug strategy when strategy is not dap", function()
      local adapter = require("neotest-scala")

      H.mock_fn("neotest-scala.metals", "get_build_target_info", function()
        return {
          ["Target"] = { "munit-test" },
          ["Base Directory"] = { "file:/tmp/project/" },
        }
      end)

      H.mock_fn("neotest-scala.metals", "get_project_name", function()
        return "munit"
      end)

      H.mock_fn("neotest-scala.metals", "get_framework", function()
        return "munit"
      end)

      H.mock_fn("neotest-scala.build", "get_tool", function()
        return "sbt"
      end)

      H.mock_fn("neotest-scala.framework", "get_framework_class", function()
        return {
          build_command = function()
            return { "echo", "ok" }
          end,
        }
      end)

      adapter({ cache_build_info = false })

      local spec = adapter.build_spec({
        tree = {
          data = function()
            return {
              type = "test",
              path = "/tmp/project/src/test/scala/ExampleSpec.scala",
              name = "\"works\"",
            }
          end,
        },
        strategy = "integrated",
        extra_args = {},
      })

      assert.is_nil(spec.strategy)
    end)
  end)

  describe("metals buildTargetChanged handler", function()
    local original_get_client_by_id
    local original_schedule
    local original_handler

    before_each(function()
      original_get_client_by_id = vim.lsp.get_client_by_id
      original_schedule = vim.schedule
      original_handler = vim.lsp.handlers["metals/buildTargetChanged"]
    end)

    after_each(function()
      vim.lsp.get_client_by_id = original_get_client_by_id
      vim.schedule = original_schedule
      vim.lsp.handlers["metals/buildTargetChanged"] = original_handler
      local ok, metals = pcall(require, "neotest-scala.metals")
      if ok and metals.cleanup then
        metals.cleanup()
      end
    end)

    it("chains previous handler and invalidates cache for the metals root", function()
      local metals = require("neotest-scala.metals")
      metals.cleanup()

      local previous_called = false
      local invalidated_root = nil

      local previous = function(_, _, _)
        previous_called = true
      end

      vim.lsp.handlers["metals/buildTargetChanged"] = previous

      H.mock_fn("neotest-scala.metals", "invalidate_cache", function(root_path)
        invalidated_root = root_path
      end)

      vim.lsp.get_client_by_id = function(_)
        return { config = { root_dir = "/tmp/project" } }
      end
      vim.schedule = function(cb)
        cb()
      end

      metals.setup()

      local handler = vim.lsp.handlers["metals/buildTargetChanged"]
      assert.is_function(handler)

      handler(nil, {}, { client_id = 42 })
      vim.wait(100, function()
        return invalidated_root ~= nil
      end)

      assert.is_true(previous_called)
      assert.are.equal("/tmp/project", invalidated_root)

      metals.cleanup()
      assert.are.equal(previous, vim.lsp.handlers["metals/buildTargetChanged"])
    end)
  end)
end)
