package com.example

import org.scalatest.propspec.AnyPropSpec
import org.scalatest.matchers.should.Matchers

class PropSpec extends AnyPropSpec with Matchers {

  property("string length succeeds") {
    "hello".length shouldEqual 5
  }

  property("string length fails") {
    "hello".length shouldEqual 999
  }

  property("property throws exception") {
    throw new RuntimeException("propspec crash")
  }
}
