package com.example

import org.scalatest.wordspec.AnyWordSpec
import org.scalatest.matchers.should.Matchers

class WordSpec extends AnyWordSpec with Matchers {
  "A calculator" should {
    "add numbers successfully" in {
      (1 + 1) shouldEqual 2
    }

    "show a failing assertion" in {
      (2 * 2) shouldEqual 5
    }

    "throw an exception in test body" in {
      throw new RuntimeException("wordspec boom")
    }
  }
}
