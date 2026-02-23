package com.example

// a HelloWorldSpec that just verifies that scalatest's FunSuite is working
import org.scalatest.funsuite.AnyFunSuite

import org.scalatest.matchers.should.Matchers
import scala.util.control.NoStackTrace

class FunSuiteSpec extends AnyFunSuite with Matchers {

  test("Hello, & ScalaTest!") {
    1 shouldEqual 1
  }
  test("failing test") {
    1 shouldEqual 2
  }
  test("crashing test") {
    throw new RuntimeException("kaboom")
  }
  test("crashing with custom exception") {
    throw Boom
  }

  // TODO: exceptions during initialisation should show everything red
  // throw new RuntimeException("kekw")
}

object Boom extends NoStackTrace {
  override def getMessage: String = "Boom!"
}
