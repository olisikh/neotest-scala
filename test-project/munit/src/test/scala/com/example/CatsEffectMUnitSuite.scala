package com.example

import cats.effect.IO
import munit.CatsEffectSuite

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
