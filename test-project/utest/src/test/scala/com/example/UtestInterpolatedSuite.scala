package com.example

import utest._

object UTestInterpolatedSuite extends TestSuite {

  private val baseName = "dynamic-case"

  val tests = Tests {
    test(s"${baseName}-pass") {
      1 ==> 1
    }

    test(s"${baseName}-fail") {
      1 ==> 2
    }

    test(s"${baseName}-crash") {
      throw new RuntimeException("utest interpolated crash")
    }
  }
}
