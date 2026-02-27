package com.example

import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers

class FunSpec extends AnyFunSpec with Matchers {
  describe("List operations") {
    it("supports successful checks") {
      List(1, 2, 3).sum shouldEqual 6
    }

    it("contains a failing assertion") {
      List(1, 2, 3).head shouldEqual 99
    }

    it("can throw from test code") {
      throw new IllegalStateException("funspec crash")
    }
  }
}
