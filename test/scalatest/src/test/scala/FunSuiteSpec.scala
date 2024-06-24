// a HelloWorldSpec that just verifies that scalatest's FunSuite is working
import org.scalatest.funsuite.AnyFunSuite

class FunSuiteSpec extends AnyFunSuite {
  test("Hello, & ScalaTest!") {
    assert(1 == 1)
  }
  test("failing test") {
    assert(1 == 2)
  }
}
