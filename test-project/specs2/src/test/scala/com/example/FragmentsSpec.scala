package com.example

import org.specs2.Specification
import org.specs2.execute.Result

class FragmentsSpec extends Specification {

  def is =
    "Fragments spec" ^
      "fragment success" ! fragmentSuccess ^
      "fragment failure" ! fragmentFailure ^
      "fragment crash" ! fragmentCrash

  def fragmentSuccess = ok
  def fragmentFailure = ko("fragment failure")
  def fragmentCrash: Result = throw new RuntimeException("fragment crash")
}
