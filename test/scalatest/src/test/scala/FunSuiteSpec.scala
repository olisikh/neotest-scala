// a HelloWorldSpec that just verifies that scalatest's FunSuite is working
import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

class FunSuiteSpec extends AnyFunSuite with Matchers {
  test("Hello, & ScalaTest!") {
    (1 shouldEqual 1)
  }
  test("failing test") {
    (1 shouldEqual 2)
  }
  test("crashing test") {
    throw new RuntimeException("kaboom")
  }
}
