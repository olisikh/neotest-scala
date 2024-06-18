// scalatest AnyFreeSpec test
import org.scalatest.freespec.AnyFreeSpec
import org.scalatest.matchers.should.Matchers

class FreeSpecSpec extends AnyFreeSpec with Matchers {

  "HelloWorldSpec" - {
    "Hello, ScalaTest!" in {
      1 shouldEqual 1
    }
    "failing test" in {
      1 shouldEqual 2
    }
  }
}
