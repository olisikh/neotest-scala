// scalatest AnyFreeSpec test
import org.scalatest.freespec.AnyFreeSpec
import org.scalatest.matchers.should.Matchers

class MySpecSpec extends AnyFreeSpec with Matchers {

  "HelloWorldSpec" - {
    "Hello, ScalaTest!" in {
      1 shouldEqual 1
    }
    "failing test" in {
      1 shouldEqual 2
    }
    "deeply" - {
      "nested" in {
        1 shouldEqual 5
      }
    }
    "failing" in {
      throw new RuntimeException("boom")
    }
  }
}
