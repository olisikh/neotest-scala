package com.example

import org.specs2.Specification
import org.specs2.matcher.Matchers

class ImmutableSpec extends Specification with Matchers {

  def is = s2"""
    immutable success example  $okExample
    immutable failing example  $failingExample
  """

  def okExample = 1 must equalTo(1)
  def failingExample = 1 must equalTo(2)
}
