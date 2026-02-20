package com.example

import org.specs2.mutable.Specification

class MutableSpec extends Specification {

  "HelloWereld" >> {
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
      "a crashing test" >> {
        throw new RuntimeException("babbahh")
        1 must equalTo(1)
      }
    }
  }
}
