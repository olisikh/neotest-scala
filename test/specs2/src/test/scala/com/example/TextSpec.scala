package com.example

import org.specs2.mutable.Specification

// TODO: not supported, can't use treesitter for parsing positions, should parse string somehow
// and use string ranges to render errors / successes
class HelloWorldSpec extends Specification:

  override def is = sequential ^ s2"""

  This is a specification for the 'Hello world' string

  The 'Hello world' string should
    contain 11 characters $e1
    start with 'Hello' $e2
    end with 'world' $e3

  """

  def e1 = "Hello world" must haveSize(11)
  def e2 = "Hello world" must startWith("Hello")
  def e3 = "Hello world" must endWith("world")
