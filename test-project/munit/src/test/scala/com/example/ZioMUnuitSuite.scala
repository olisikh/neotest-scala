import munit.*
import zio.*

class SimpleZIOSpec extends ZSuite:
  testZ("1 + 1 = 2") {
    for
      a <- ZIO.attempt(1)
      b <- ZIO.attempt(1)
    yield assertEquals(a + b, 2)
  }

  testZ("1 + 1 = 3") {
    for
      a <- ZIO.attempt(1)
      b <- ZIO.attempt(1)
    yield assertEquals(a + b, 3)
  }

  testZ("crash with exception") {
    ZIO.fail(new RuntimeException("zio crash"))
  }
