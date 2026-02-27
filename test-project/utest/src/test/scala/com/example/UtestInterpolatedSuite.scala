package com.example

import utest._

object UtestInterpolatedSuite extends TestSuite {
  private val baseName = "dynamic-case"

  val tests = Tests {
    test(s"${baseName}-pass") {
      1 ==> 1
    }

    test(s"${baseName}-fail") {
      1 ==> 2
    }

    val runtimeName = s"${baseName}-crash"
    test(runtimeName) {
      throw new RuntimeException("utest interpolated crash")
    }
  }
}
