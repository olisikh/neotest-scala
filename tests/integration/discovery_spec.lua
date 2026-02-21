local H = require("tests.helpers")

package.loaded["neotest.lib"] = package.loaded["neotest.lib"] or {
  files = {
    read_lines = function(_)
      return { "package com.example" }
    end,
  },
}

describe("metals get_frameworks", function()
  local metals = require("neotest-scala.metals")

  local original_get_build_target_info

  before_each(function()
    original_get_build_target_info = metals.get_build_target_info
  end)

  after_each(function()
    metals.get_build_target_info = original_get_build_target_info
  end)

  it("detects scalatest from classpath", function()
    metals.get_build_target_info = function()
      return {
        ["Scala Classpath"] = {
          "org/scalatest/scalatest_3-3.2.0.jar",
          "org/scala-lang/scala3-library_3-3.0.0.jar",
        },
      }
    end

    local frameworks = metals.get_frameworks("/root", "/root/test.scala", false)
    assert.are.same({ "scalatest" }, frameworks)
  end)

  it("detects munit from classpath", function()
    metals.get_build_target_info = function()
      return {
        ["Scala Classpath"] = {
          "org/scalameta/munit_3-0.7.0.jar",
          "org/scala-lang/scala3-library_3-3.0.0.jar",
        },
      }
    end

    local frameworks = metals.get_frameworks("/root", "/root/test.scala", false)
    assert.are.same({ "munit" }, frameworks)
  end)

  it("detects specs2 from classpath", function()
    metals.get_build_target_info = function()
      return {
        ["Scala Classpath"] = {
          "org/specs2/specs2-core_3-4.14.0.jar",
          "org/scala-lang/scala3-library_3-3.0.0.jar",
        },
      }
    end

    local frameworks = metals.get_frameworks("/root", "/root/test.scala", false)
    assert.are.same({ "specs2" }, frameworks)
  end)

  it("detects utest from classpath", function()
    metals.get_build_target_info = function()
      return {
        ["Scala Classpath"] = {
          "com/lihaoyi/utest_3-0.7.0.jar",
          "org/scala-lang/scala3-library_3-3.0.0.jar",
        },
      }
    end

    local frameworks = metals.get_frameworks("/root", "/root/test.scala", false)
    assert.are.same({ "utest" }, frameworks)
  end)

  it("detects zio-test from classpath", function()
    metals.get_build_target_info = function()
      return {
        ["Scala Classpath"] = {
          "dev/zio/zio-test_3-2.0.0.jar",
          "org/scala-lang/scala3-library_3-3.0.0.jar",
        },
      }
    end

    local frameworks = metals.get_frameworks("/root", "/root/test.scala", false)
    assert.are.same({ "zio-test" }, frameworks)
  end)

  it("detects multiple frameworks", function()
    metals.get_build_target_info = function()
      return {
        ["Scala Classpath"] = {
          "org/scalatest/scalatest_3-3.2.0.jar",
          "org/scalameta/munit_3-0.7.0.jar",
          "org/scala-lang/scala3-library_3-3.0.0.jar",
        },
      }
    end

    local frameworks = metals.get_frameworks("/root", "/root/test.scala", false)
    assert.are.same({ "scalatest", "munit" }, frameworks)
  end)

  it("detects all frameworks", function()
    metals.get_build_target_info = function()
      return {
        ["Scala Classpath"] = {
          "org/scalatest/scalatest_3-3.2.0.jar",
          "org/scalameta/munit_3-0.7.0.jar",
          "org/specs2/specs2-core_3-4.14.0.jar",
          "com/lihaoyi/utest_3-0.7.0.jar",
          "dev/zio/zio-test_3-2.0.0.jar",
          "org/scala-lang/scala3-library_3-3.0.0.jar",
        },
      }
    end

    local frameworks = metals.get_frameworks("/root", "/root/test.scala", false)
    assert.are.same({ "scalatest", "munit", "specs2", "utest", "zio-test" }, frameworks)
  end)

  it("returns empty array when no build info", function()
    metals.get_build_target_info = function()
      return nil
    end

    local frameworks = metals.get_frameworks("/root", "/root/test.scala", false)
    assert.are.same({}, frameworks)
  end)

  it("returns empty array when no classpath", function()
    metals.get_build_target_info = function()
      return {
        ["Sources"] = { "src/test/scala" },
      }
    end

    local frameworks = metals.get_frameworks("/root", "/root/test.scala", false)
    assert.are.same({}, frameworks)
  end)

  it("returns empty array when classpath is empty", function()
    metals.get_build_target_info = function()
      return {
        ["Scala Classpath"] = {},
      }
    end

    local frameworks = metals.get_frameworks("/root", "/root/test.scala", false)
    assert.are.same({}, frameworks)
  end)

  it("handles Classpath field instead of Scala Classpath", function()
    metals.get_build_target_info = function()
      return {
        ["Classpath"] = {
          "org/scalatest/scalatest_3-3.2.0.jar",
        },
      }
    end

    local frameworks = metals.get_frameworks("/root", "/root/test.scala", false)
    assert.are.same({ "scalatest" }, frameworks)
  end)
end)

describe("scalatest detect_style", function()
  local scalatest = require("neotest-scala.framework.scalatest")

  it("detects funsuite style", function()
    local content = [[
package com.example

class MySpec extends AnyFunSuite {
  test("should pass") {
    assert(true)
  }
}
]]
    local style = scalatest.detect_style(content)
    assert.are.equal("funsuite", style)
  end)

  it("detects funsuite with munit prefix", function()
    local content = [[
package com.example

class MySpec extends munit.FunSuite {
  test("should pass") {
    assert(true)
  }
}
]]
    local style = scalatest.detect_style(content)
    assert.are.equal("funsuite", style)
  end)

  it("detects freespec style", function()
    local content = [[
package com.example

class MySpec extends AnyFreeSpec {
  "A condition" - {
    "should pass" in {
      assert(true)
    }
  }
}
]]
    local style = scalatest.detect_style(content)
    assert.are.equal("freespec", style)
  end)

  it("detects freespec with prefix", function()
    local content = [[
package com.example

class MySpec extends org.scalatest.freespec.AnyFreeSpec {
  "A condition" - {
    "should pass" in {
      assert(true)
    }
  }
}
]]
    local style = scalatest.detect_style(content)
    assert.are.equal("freespec", style)
  end)

  it("returns nil for non-scalatest content", function()
    local content = [[
package com.example

class MySpec {
  def test(): Unit = {}
}
]]
    local style = scalatest.detect_style(content)
    assert.is_nil(style)
  end)
end)

describe("munit detect_style", function()
  local munit = require("neotest-scala.framework.munit")

  it("detects funsuite style", function()
    local content = [[
package com.example

class MySpec extends FunSuite {
  test("should pass") {
    assert(true)
  }
}
]]
    local style = munit.detect_style(content)
    assert.are.equal("funsuite", style)
  end)

  it("detects funsuite with munit prefix", function()
    local content = [[
package com.example

class MySpec extends munit.FunSuite {
  test("should pass") {
    assert(true)
  }
}
]]
    local style = munit.detect_style(content)
    assert.are.equal("funsuite", style)
  end)

  it("returns nil for non-munit content", function()
    local content = [[
package com.example

class MySpec {
  def test(): Unit = {}
}
]]
    local style = munit.detect_style(content)
    assert.is_nil(style)
  end)
end)

describe("specs2 detect_style", function()
  local specs2 = require("neotest-scala.framework.specs2")

  it("detects text style", function()
    local content = [[
package com.example

class MySpec extends Specification {
  s2"""A test scenario""" should {
    "pass" in ok
  }
}
]]
    local style = specs2.detect_style(content)
    assert.are.equal("text", style)
  end)

  it("detects mutable style", function()
    local content = [[
package com.example

class MySpec extends Specification {
  "A test" >> {
    ok
  }
}
]]
    local style = specs2.detect_style(content)
    assert.are.equal("mutable", style)
  end)

  it("returns nil for non-specs2 content", function()
    local content = [[
package com.example

class MySpec {
  def test(): Unit = {}
}
]]
    local style = specs2.detect_style(content)
    assert.is_nil(style)
  end)
end)

describe("utest detect_style", function()
  local utest = require("neotest-scala.framework.utest")

  it("detects suite style", function()
    local content = [[
package com.example

object MySpec extends TestSuite {
  test("should pass") {
    assert(true)
  }
}
]]
    local style = utest.detect_style(content)
    assert.are.equal("suite", style)
  end)

  it("detects suite with utest reference", function()
    local content = [[
package com.example

import utest._

object MySpec extends TestSuite {
  test("should pass") {
    assert(true)
  }
}
]]
    local style = utest.detect_style(content)
    assert.are.equal("suite", style)
  end)

  it("returns nil for non-utest content", function()
    local content = [[
package com.example

class MySpec {
  def test(): Unit = {}
}
]]
    local style = utest.detect_style(content)
    assert.is_nil(style)
  end)
end)

describe("zio-test detect_style", function()
  local zio_test = require("neotest-scala.framework.zio-test")

  it("detects spec style", function()
    local content = [[
package com.example

import zio.test._

object MySpec extends ZIOSpecDefault {
  test("should pass") {
    assertTrue(true)
  }
}
]]
    local style = zio_test.detect_style(content)
    assert.are.equal("spec", style)
  end)

  it("detects spec with zio.test prefix", function()
    local content = [[
package com.example

class MySpec extends ZIOSpecDefault {
  test("should pass") {
    assertTrue(true)
  }
}
]]
    local style = zio_test.detect_style(content)
    assert.are.equal("spec", style)
  end)

  it("returns nil for non-zio-test content", function()
    local content = [[
package com.example

class MySpec {
  def test(): Unit = {}
}
]]
    local style = zio_test.detect_style(content)
    assert.is_nil(style)
  end)
end)

describe("multi-framework scenarios", function()
  local metals = require("neotest-scala.metals")
  local scalatest = require("neotest-scala.framework.scalatest")
  local munit = require("neotest-scala.framework.munit")

  local original_get_build_target_info

  before_each(function()
    original_get_build_target_info = metals.get_build_target_info
  end)

  after_each(function()
    metals.get_build_target_info = original_get_build_target_info
  end)

  it("framework detection works with mixed classpath entries", function()
    metals.get_build_target_info = function()
      return {
        ["Scala Classpath"] = {
          "org/scalatest/scalatest_3-3.2.0.jar",
          "com/typesafe/config-1.4.0.jar",
          "org/scalameta/munit_3-0.7.0.jar",
          "org/scala-lang/scala-library-2.13.8.jar",
        },
      }
    end

    local frameworks = metals.get_frameworks("/root", "/root/test.scala", false)
    assert.are.same({ "scalatest", "munit" }, frameworks)
  end)

  it("framework detection handles version suffixes", function()
    metals.get_build_target_info = function()
      return {
        ["Scala Classpath"] = {
          "org/scalatest/scalatest_2.13-3.2.9.jar",
          "org/scalatest/scalatest_3-3.2.0-RC1.jar",
          "org/scalatest/scalatest_2.12-3.1.2.jar",
        },
      }
    end

    local frameworks = metals.get_frameworks("/root", "/root/test.scala", false)
    assert.are.same({ "scalatest" }, frameworks)
  end)

  it("framework detection handles snapshot versions", function()
    metals.get_build_target_info = function()
      return {
        ["Scala Classpath"] = {
          "org/scalatest/scalatest_3-3.2.0-SNAPSHOT.jar",
        },
      }
    end

    local frameworks = metals.get_frameworks("/root", "/root/test.scala", false)
    assert.are.same({ "scalatest" }, frameworks)
  end)

  it("detect_style returns nil for empty content", function()
    local style = scalatest.detect_style("")
    assert.is_nil(style)
  end)

  it("detect_style returns nil for whitespace-only content", function()
    local style = munit.detect_style("   \n\t  ")
    assert.is_nil(style)
  end)
end)
