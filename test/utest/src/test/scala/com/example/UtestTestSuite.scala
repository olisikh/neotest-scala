package com.example

import utest._

object UtestTestSuite extends TestSuite {

  val tests = Tests {
    test("Hello, utest!") {
      1 ==> 1
    }
    test("failing test") {
      1 ==> 2
    }

    test("crashing test") {
      throw new RuntimeException("Hello world")
    }
  }

  // throw new RuntimeException("Hello world")
}
