package com.example

import munit.DisciplineSuite
import org.scalacheck.Prop.forAll

class DisciplineMUnitSuite extends DisciplineSuite {
  test("discipline style success") {
    assertEquals("abc".startsWith("a"), true)
  }

  test("discipline style failure") {
    assertEquals(List(1, 2).size, 99)
  }

  property("property in discipline suite") {
    forAll { (a: Int, b: Int) =>
      a + b == b + a
    }
  }

  test("discipline crash") {
    throw new IllegalStateException("discipline suite crash")
  }
}
