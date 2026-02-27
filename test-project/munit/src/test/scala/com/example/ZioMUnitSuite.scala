package com.example

import munit.*
import zio.*

class ZioMUnitSuite extends ZSuite:
  testZ("zio success") {
    for
      one <- ZIO.attempt(1)
      two <- ZIO.attempt(1)
    yield assertEquals(one + two, 2)
  }

  testZ("zio failure") {
    for
      one <- ZIO.attempt(1)
      two <- ZIO.attempt(1)
    yield assertEquals(one + two, 3)
  }

  testZ("zio crash") {
    ZIO.fail(new RuntimeException("zio crash"))
  }
