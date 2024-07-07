package com.example

import munit._

class MUnitSuite extends FunSuite {
  test("Hello, MUnit!") {
    assert(1 == 1)
  }
  test("failing test") {
    assert(1 == 2)
  }
  test("crashing test") {
    throw new RuntimeException("kaboom!")
  }
}
