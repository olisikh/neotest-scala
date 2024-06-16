import zio.{test => _, _}
import zio.test._
import zio.test.Assertion._

object ZioTestOtherSpec extends ZIOSpecDefault {

  def spec = suite("OtherSpec")(
    test("Goodbye, zio-test!") {
      for {
        one <- ZIO.succeed(1)
        two <- ZIO.succeed(2)
      } yield assertTrue(one + two == 3)
    },
    test("crashing test") {
      for {
        one <- ZIO.succeed(1)
        two <- ZIO.succeed(2)
        _ <- ZIO.fail(new RuntimeException("oh no, boom"))
      } yield assertTrue(one + two == 2)
    }
  )
}
