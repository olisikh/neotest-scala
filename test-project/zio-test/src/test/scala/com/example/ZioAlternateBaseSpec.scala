package com.example

import zio._
import zio.test._

trait ZioBaseSpec extends ZIOSpecDefault

object ZioAlternateBaseSpec extends ZioBaseSpec {
  def spec = suite("zio2-alternate-base")(
    test("alternate base success") {
      ZIO.succeed(assertTrue(2 + 2 == 4))
    },
    test("alternate base failure") {
      ZIO.succeed(assertTrue(2 + 2 == 5))
    },
    test("alternate base crash") {
      ZIO.fail(new RuntimeException("zio2 alternate base crash"))
    }
  )
}
