package com.example

import org.specs2.mutable.Specification
import org.specs2.matcher.Matchers

class TextWithoutRefsSpec extends Specification with Matchers {
  override def is = s2"""
    TextSpec examples without dollar references

    this example should pass
    this example should fail
    this example should crash
  """

  "this example should pass" in {
    1 must equalTo(1)
  }

  "this example should fail" in {
    1 must equalTo(2)
  }

  "this example should crash" in {
    throw new RuntimeException("textspec no-ref crash")
    1 must equalTo(1)
  }
}
