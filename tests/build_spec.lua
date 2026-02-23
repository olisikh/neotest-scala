local build = require("neotest-scala.build")

describe("build", function()
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
end)
