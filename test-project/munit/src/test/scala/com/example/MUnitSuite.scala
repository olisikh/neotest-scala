package com.example

import munit._
import munit.Assertions._
import scala.util.control.NoStackTrace

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
  test("custom exception") {
    throw Boom
  }

  // throw Boom

  // TODO: exceptions during initialisation should show everything red
  // throw new RuntimeException("kekw")
}

object Boom extends NoStackTrace {
  override def getMessage: String = "Boom!"
}
