package com.example

import zio.{test => _, _}
import zio.test._
import zio.test.Assertion._

object ZioTestSpec extends ZIOSpecDefault {

  def spec = suite("HelloWorldSpec")(
    suite("hello suite") {
      test("hello") {
        for {
          one <- ZIO.succeed(1)
          two <- ZIO.succeed(2)
        } yield assertTrue(one + two == 3)
      }
    },
    test("failing test") {
      for {
        one <- ZIO.succeed(1)
        two <- ZIO.succeed(2)
      } yield assertTrue(one + two == 2)
    },
    test("more complex test") {
      for {
        value <- ZIO.none
      } yield assert(value)(isSome(equalTo(3)))
    }
  )
}
