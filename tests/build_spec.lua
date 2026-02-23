local build = require("neotest-scala.build")
local H = require("tests.helpers")

describe("build", function()
  after_each(function()
    H.restore_mocks()
  end)

  describe("merge_args", function()
    it("returns nil when both args are nil", function()
      assert.is_nil(build.merge_args(nil, nil))
    end)

    it("returns right when left is nil", function()
      local right = { "--no-colors" }
      local merged = build.merge_args(nil, right)
      assert.are.same(right, merged)
    end)

    it("returns left when right is nil", function()
      local left = { "--debug" }
      local merged = build.merge_args(left, nil)
      assert.are.same(left, merged)
    end)

    it("returns string unchanged when paired with nil", function()
      assert.are.equal("-v", build.merge_args("-v", nil))
      assert.are.equal("-v", build.merge_args(nil, "-v"))
    end)

    it("merges two strings into ordered list", function()
      local merged = build.merge_args("-v", "--no-colors")
      assert.are.same({ "-v", "--no-colors" }, merged)
    end)

    it("merges string and table preserving order", function()
      local merged = build.merge_args("-v", { "--no-colors", "--foo" })
      assert.are.same({ "-v", "--no-colors", "--foo" }, merged)
    end)

    it("merges table and string preserving order", function()
      local merged = build.merge_args({ "--no-colors", "--foo" }, "-v")
      assert.are.same({ "--no-colors", "--foo", "-v" }, merged)
    end)

    it("concatenates two tables", function()
      local merged = build.merge_args({ "--a", "--b" }, { "--c", "--d" })
      assert.are.same({ "--a", "--b", "--c", "--d" }, merged)
    end)

    it("treats empty table as nil", function()
      assert.are.equal("-v", build.merge_args({}, "-v"))
      assert.are.equal("-v", build.merge_args("-v", {}))
      assert.is_nil(build.merge_args({}, {}))
    end)
  end)

  describe("get_tool_from_build_target_info", function()
    it("detects sbt from Scala Classpath / Scala Classes Directory", function()
      local tool = build.get_tool_from_build_target_info({
        ["Scala Classes Directory"] = {
          "file:/Users/me/project/target/scala-3.8.1/test-classes",
        },
        ["Scala Classpath"] = {
          "/Users/me/project/target/scala-3.8.1/test-classes",
          "zio-test-sbt_3-2.1.2.jar",
        },
      })

      assert.are.equal("sbt", tool)
    end)

    it("detects bloop from Classpath containing .bloop client classes", function()
      local tool = build.get_tool_from_build_target_info({
        ["Classpath"] = {
          "/Users/me/project/.bloop/zio-test/bloop-bsp-clients-classes/test-classes-Metals-abc/",
          "zio-test-sbt_3-2.1.2.jar",
        },
      })

      assert.are.equal("bloop", tool)
    end)

    it("detects bloop from Classes Directory containing .bloop", function()
      local tool = build.get_tool_from_build_target_info({
        ["Classes Directory"] = {
          "file:///Users/me/project/.bloop/zio-test/bloop-bsp-clients-classes/test-classes-Metals-abc/",
        },
      })

      assert.are.equal("bloop", tool)
    end)

    it("does not treat zio-test-sbt jar as sbt indicator when bloop paths exist", function()
      local tool = build.get_tool_from_build_target_info({
        ["Classpath"] = {
          "/Users/me/project/.bloop/zio-test/bloop-bsp-clients-classes/test-classes-Metals-abc/",
          "/Users/me/.cache/zio-test-sbt_3-2.1.2.jar",
        },
        ["Scala Classpath"] = {
          "/Users/me/.cache/zio-test-sbt_3-2.1.2.jar",
        },
      })

      assert.are.equal("bloop", tool)
    end)

    it("returns sbt when metadata contains sbt markers", function()
      local tool = build.get_tool_from_build_target_info({
        ["Build server"] = { "sbt" },
      })

      assert.are.equal("sbt", tool)
    end)

    it("returns bloop when metadata contains bloop markers", function()
      local tool = build.get_tool_from_build_target_info({
        ["Build server"] = { "bloop" },
      })

      assert.are.equal("bloop", tool)
    end)

    it("prefers sbt when both markers are present", function()
      local tool = build.get_tool_from_build_target_info({
        ["Build server"] = { "bloop", "sbt" },
      })

      assert.are.equal("sbt", tool)
    end)

    it("returns nil when metadata does not include tool markers", function()
      local tool = build.get_tool_from_build_target_info({
        ["Target"] = { "myproject-test" },
      })

      assert.is_nil(tool)
    end)
  end)

  describe("get_tool", function()
    it("uses metals-derived sbt in auto mode", function()
      build.setup({ build_tool = "auto" })
      local tool = build.get_tool("/tmp/project", {
        ["Build server"] = { "sbt" },
      })

      assert.are.equal("sbt", tool)
    end)

    it("uses metals-derived bloop in auto mode", function()
      build.setup({ build_tool = "auto" })
      local tool = build.get_tool("/tmp/project", {
        ["Build server"] = { "bloop" },
      })

      assert.are.equal("bloop", tool)
    end)

    it("falls back to sbt when metadata has no tool and bloop is unavailable", function()
      build.setup({ build_tool = "auto" })
      H.mock_fn("neotest-scala.build", "is_bloop_available", function()
        return false
      end)

      local tool = build.get_tool("/tmp/project", {
        ["Target"] = { "myproject-test" },
      })

      assert.are.equal("sbt", tool)
    end)

    it("still falls back to bloop availability when metadata is missing", function()
      build.setup({ build_tool = "auto" })
      H.mock_fn("neotest-scala.build", "is_bloop_available", function()
        return true
      end)

      local tool = build.get_tool("/tmp/project", nil)

      assert.are.equal("bloop", tool)
    end)
  end)
end)
