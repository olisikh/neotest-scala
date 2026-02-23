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

describe("framework style detection visibility", function()
  local scalatest = require("neotest-scala.framework.scalatest")
  local munit = require("neotest-scala.framework.munit")
  local specs2 = require("neotest-scala.framework.specs2")
  local utest = require("neotest-scala.framework.utest")
  local zio_test = require("neotest-scala.framework.zio-test")

  it("keeps style detection private in scalatest", function()
    assert.is_nil(scalatest.detect_style)
  end)

  it("keeps style detection private in munit", function()
    assert.is_nil(munit.detect_style)
  end)

  it("keeps style detection private in specs2", function()
    assert.is_nil(specs2.detect_style)
  end)

  it("keeps style detection private in utest", function()
    assert.is_nil(utest.detect_style)
  end)

  it("keeps style detection private in zio-test", function()
    assert.is_nil(zio_test.detect_style)
  end)
end)

describe("multi-framework scenarios", function()
  local metals = require("neotest-scala.metals")

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

end)
