// specs2 mutable.Specification test

import org.specs2.mutable.Specification

class HelloWorldSpec extends Specification {

  "HelloWorldSpec" should {
    "Hello, Specs2!" in {
      1 must equalTo(1)
    }
    "failing test" in {
      1 must equalTo(2)
    }
  }
}
