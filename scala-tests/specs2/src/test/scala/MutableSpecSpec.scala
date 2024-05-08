// specs2 mutable.Specification test

import org.specs2.mutable.Specification

class HelloWorldSpec extends Specification {

  "HelloWorldSpec" should {
    "Hello, Specs2!" in {
      1 must equalTo(1)
    }
    "failing test" >> {
      1 should equalTo(2)
    }
    "and" >> {
      "a passing nested test" >> {
        1 must equalTo(1)
      }
      "a failing nested test" >> {
        "hello" must be("world")
      }
    }
  }
}
