import munit._

// a HelloWorldSpec that just verifies that munit is working
class HelloWorldSpec extends FunSuite {
  test("Hello, MUnit!") {
    assert(1 == 1)
  }
  test("failing test") {
    assert(1 == 2)
  }
}
