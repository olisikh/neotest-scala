# zio-test

zio-test is ZIO's built-in testing framework, designed for testing effectful programs.

## Official Documentation

- Website: [zio.dev/reference/test](https://zio.dev/reference/test/)
- Guide: [zio.dev/reference/test/overview](https://zio.dev/reference/test/overview)

## Setup

### build.sbt

```scala
libraryDependencies ++= Seq(
  "dev.zio" %% "zio" % "2.1.0",
  "dev.zio" %% "zio-test" % "2.1.0" % Test,
  "dev.zio" %% "zio-test-sbt" % "2.1.0" % Test
)
testFrameworks += new TestFramework("zio.test.sbt.ZTestFramework")
```

> **Note**: zio-test requires both the library and the sbt test framework registration.

## Basic Usage

### ZIOSpecDefault

```scala
package com.example

import zio.{test => _, _}
import zio.test._
import zio.test.Assertion._

object MySpec extends ZIOSpecDefault {
  def spec = suite("MySuite")(
    test("addition works") {
      for {
        result <- ZIO.succeed(1 + 1)
      } yield assertTrue(result == 2)
    },

    test("simple assertion") {
      assertTrue(1 + 1 == 2)
    }
  )
}
```

### suiteAll

An alternative syntax for simpler test definitions:

```scala
package com.example

import zio.{test => _, _}
import zio.test._

object MySuiteAllSpec extends ZIOSpecDefault {
  def spec = suiteAll("MySuite") {
    test("first test") {
      assertTrue(1 == 1)
    }

    test("second test") {
      for {
        value <- ZIO.succeed(42)
      } yield assertTrue(value == 42)
    }

    suite("nested suite") {
      test("nested test") {
        assertTrue(true)
      }
    }
  }
}
```

## Test Discovery

| Syntax | Detected | Example |
|--------|----------|---------|
| `test("name") { }` | ✅ | Standard test |
| `suite("name") { }` | ✅ | Test suite |
| `suiteAll("name") { }` | ✅ | Alternative suite |

## Test Commands

### Run All Tests in Object

```bash
sbt <project>/testOnly com.example.MySpec
```

### Run Single Test

```bash
sbt <project>/testOnly com.example.MySpec -- -t "addition works"
```

The `-t` flag filters tests by exact name match.

## Assertions

### assertTrue (Recommended)

```scala
test("modern assertions") {
  val value = 42
  assertTrue(value == 42)
  assertTrue(value > 0)
  assertTrue(value < 100)
}
```

### Legacy Assertions

```scala
test("legacy assertions") {
  for {
    value <- ZIO.succeed(Some(42))
  } yield assert(value)(isSome(equalTo(42)))
}

test("collection assertions") {
  val list = List(1, 2, 3)
  assert(list)(hasSize(equalTo(3)))
}
```

## ZIO-Specific Features

### Testing ZIO Effects

```scala
test("effect testing") {
  for {
    result <- ZIO.attempt(1 / 1)
  } yield assertTrue(result == 1)
}

test("testing failures") {
  val effect = ZIO.fail("error")
  assertZIO(effect.exit)(fails(equalTo("error")))
}
```

### Test Services (Environment)

```scala
object ServiceSpec extends ZIOSpecDefault {
  def spec = suite("with test services") {
    test("use mocked service") {
      for {
        result <- MyService.doSomething
      } yield assertTrue(result == "mocked")
    }
  }.provide(
    MyService.test // Test implementation
  )
}
```

### TestClock

```scala
test("time-based effects") {
  for {
    fiber <- ZIO.sleep(1.hour).fork
    _     <- TestClock.adjust(1.hour)
    _     <- fiber.join
  } yield assertTrue(true)
}
```

## Debugging

zio-test supports debugging individual tests:

```lua
require('neotest').run.run({ strategy = 'dap' })
```

See [[Debugging]] for setup instructions.

## Nested Tests

zio-test supports deeply nested test structures:

```scala
def spec = suite("outer")(
  suite("middle")(
    suite("inner")(
      test("deep test") {
        assertTrue(true)
      }
    )
  )
)
```

All nesting levels are detected and shown in the Neotest summary.

## Result Parsing

neotest-scala has custom result parsing for zio-test:

- Parses zio-test's specific JUnit XML output format
- Extracts error line numbers from stack traces
- Handles the `-` / `x` prefix notation in test output

## Tips

### Use assertTrue for Better Errors

```scala
// Preferred - clear failure messages
assertTrue(complexValue == expected)

// Less preferred - generic assertion failure
assert(complexValue)(equalTo(expected))
```

### Group Tests by Feature

```scala
def spec = suite("UserRepository")(
  suite("create")(
    test("creates a new user") { ... },
    test("validates input") { ... }
  ),
  suite("delete")(
    test("removes existing user") { ... }
  )
)
```

### Provide Test Layers

```scala
def spec = suite("integration tests") {
  test("database operation") {
    for {
      result <- Database.query
    } yield assertTrue(result.nonEmpty)
  }
}.provideLayer(Database.test)
```

## Related Pages

- [[Supported Test Libraries|3.-Supported-Test-Libraries]] — All libraries overview
- [[Debugging]] — Debugging setup
- [[Configuration|2.-Configuration]] — Configuration options
