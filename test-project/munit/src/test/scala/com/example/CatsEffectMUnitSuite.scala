package com.example

import munit.CatsEffectSuite
import cats.effect.IO

class CatsEffectMUnitSuite extends CatsEffectSuite {

  test("io success") {
    IO(assertEquals(1 + 1, 2))
  }

  test("io failure") {
    IO(assertEquals(1 + 1, 3))
  }

  test("io crash") {
    IO.raiseError(new RuntimeException("cats effect crash"))
  }
}
