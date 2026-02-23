package com.example

// scalatest AnyFreeSpec test
import org.scalatest.freespec.AnyFreeSpec
import org.scalatest.matchers.should.Matchers
import scala.util.control.NoStackTrace

class FreeSpec extends AnyFreeSpec with Matchers {

  "FreeSpec" - {
    "Hello, ScalaTest!" in {
      1 shouldEqual 1
    }
    "deeeeeeeeep" - {
      "even deeeeeeeeeper" - {
        "test" in {
          1 shouldEqual 2
        }
      }
    }
    "failing test" in {
      1 shouldEqual 2
    }
    "deeply" - {
      "nested" - {
        "event more nested lol" in {
          1 shouldEqual 5
        }
      }
    }
    "failing" in {
      throw new RuntimeException("boom")
    }
    "custom exception" in {
      throw Babbah
    }
  }
}

object Babbah extends NoStackTrace {
  override def toString: String = "Boomchik"
}
