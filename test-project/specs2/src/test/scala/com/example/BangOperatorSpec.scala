package com.example

import org.specs2.mutable.Specification
import org.specs2.matcher.Matchers

class BangOperatorSpec extends Specification with Matchers {

  "bang operator success" ! {
    1 must equalTo(1)
  }

  "bang operator failure" ! {
    1 must equalTo(2)
  }

  "bang operator crash" ! {
    throw new RuntimeException("bang operator crash")
    1 must equalTo(1)
  }
}
