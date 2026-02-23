package com.example

// a HelloWorldSpec that just verifies that scalatest's FunSuite is working
import org.scalatest.flatspec.AnyFlatSpec

import org.scalatest.matchers.should.Matchers
import scala.util.control.NoStackTrace
import scala.collection.mutable.Stack

class FlatSpec extends AnyFlatSpec with Matchers {

  val emptyStack = new Stack[Int]

  // behavior of "A Stack" - is an alternative to "XYZ" should
  "A Stack" should "pop values in last-in-first-out order" in {
    val stack = new Stack[Int]
    stack.push(1)
    stack.push(2)
    assert(stack.pop() === 2)
    assert(stack.pop() === 1)
  }

  it should "throw NoSuchElementException if an empty stack is popped" in {
    val emptyStack = new Stack[String]
    intercept[NoSuchElementException] {
      emptyStack.pop()
    }
  }

  it should "fail" in {
    1 shouldEqual 2
  }

  it should "crash" in {
    throw new RuntimeException("boom")
  }
}
