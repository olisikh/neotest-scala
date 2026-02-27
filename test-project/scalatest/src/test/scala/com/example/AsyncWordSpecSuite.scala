package com.example

import org.scalatest.wordspec.AsyncWordSpec
import org.scalatest.matchers.should.Matchers
import scala.concurrent.Future

class AsyncWordSpecSuite extends AsyncWordSpec with Matchers {
  "An async service" should {
    "complete successfully" in {
      Future.successful(1 + 1).map(_ shouldEqual 2)
    }

    "show an async failure" in {
      Future.successful(1 + 1).map(_ shouldEqual 3)
    }

    "fail with exception" in {
      Future.failed(new RuntimeException("async wordspec crash"))
    }
  }
}
