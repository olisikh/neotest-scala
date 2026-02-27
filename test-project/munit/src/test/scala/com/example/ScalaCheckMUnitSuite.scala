package com.example

import munit.ScalaCheckSuite
import org.scalacheck.Prop.forAll

class ScalaCheckMUnitSuite extends ScalaCheckSuite {
  property("reverse reverse is identity") {
    forAll { (xs: List[Int]) =>
      xs.reverse.reverse == xs
    }
  }

  property("intentionally failing property") {
    forAll { (n: Int) =>
      n + 1 == n
    }
  }

  test("regular test that crashes") {
    throw new RuntimeException("scalacheck suite crash")
  }
}
