package com.example

import org.scalatest.featurespec.AnyFeatureSpec
import org.scalatest.matchers.should.Matchers

class FeatureSpec extends AnyFeatureSpec with Matchers {

  Feature("Authentication") {
    Scenario("successful login") {
      "token" shouldEqual "token"
    }

    Scenario("failing credential check") {
      401 shouldEqual 200
    }

    Scenario("unexpected exception") {
      throw new RuntimeException("featurespec crash")
    }
  }
}
