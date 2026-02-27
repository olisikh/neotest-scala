package com.example

import org.scalatest.funsuite.FixtureAnyFunSuite

class FixtureFunSuite extends FixtureAnyFunSuite {
  type FixtureParam = String

  override protected def withFixture(test: OneArgTest) = {
    test("fixture-value")
  }

  test("fixture success") { fixture =>
    assert(fixture == "fixture-value")
  }

  test("fixture failure") { fixture =>
    assert(fixture == "wrong-value")
  }

  test("fixture crash") { _ =>
    throw new RuntimeException("fixture suite crash")
  }
}
