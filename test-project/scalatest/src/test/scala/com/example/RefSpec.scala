package com.example

import org.scalatest.refspec.RefSpec
import org.scalatest.matchers.should.Matchers

class SampleRefSpec extends RefSpec  with Matchers {

  object Testing {
    def `successful example`(): Unit = {
      10 shouldEqual 10
    }

    def `failing example`(): Unit = {
      10 shouldEqual 11
    }

    def `crashing example`(): Unit = {
      throw new RuntimeException("refspec crash")
    }
  }
}
