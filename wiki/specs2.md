# specs2

specs2 is a specification-based testing library for Scala that supports both mutable and immutable specification styles.

## Official Documentation

- Website: [etorreborre.github.io/specs2](https://etorreborre.github.io/specs2)
- Guide: [etorreborre.github.io/specs2/guide](https://etorreborre.github.io/specs2/guide/)

## Setup

### build.sbt

```scala
libraryDependencies += "org.specs2" %% "specs2-core" % "4.20.3" % Test
```

## Supported Styles

### mutable.Specification

The mutable style uses `>>` and `in` operators:

```scala
import org.specs2.mutable.Specification

class MySpec extends Specification {
  "My Feature" >> {
    "should work correctly" in {
      1 mustEqual 1
    }

    "should handle errors" in {
      1 must beEqualTo(1)
    }

    "nested context" >> {
      "with nested test" in {
        true must beTrue
      }
    }
  }
}
```

### Test Syntax Detection

| Syntax | Detected | Notes |
|--------|----------|-------|
| `"name" in { }` | ✅ | Standard test |
| `"name" >> { }` | ✅ | Alternative syntax |
| `"name" should { }` | ✅ | BDD-style |
| `"name" can { }` | ✅ | BDD-style |

## Test Commands

### Run All Tests in Class

```bash
sbt <project>/testOnly com.example.MySpec
```

### Run Single Test

```bash
# Limited support - runs full spec
sbt <project>/testOnly com.example.MySpec
```

> **Note**: specs2 has limited support for running individual tests due to framework limitations. The `-- ex` syntax is available but has issues with tests containing brackets or grouped tests.

## Features

### Matchers

```scala
class MatcherSpec extends Specification {
  "Matchers" >> {
    "equality" in {
      1 mustEqual 1
      1 must beEqualTo(1)
      1 === 1
    }

    "comparison" in {
      1 must beLessThan(2)
      1 must beGreaterThan(0)
    }

    "collections" in {
      List(1, 2, 3) must contain(2)
      List(1, 2, 3) must haveSize(3)
    }

    "strings" in {
      "hello" must startWith("he")
      "hello" must endWith("lo")
      "hello" must contain("ell")
    }
  }
}
```

### Data Tables

```scala
class TableSpec extends Specification {
  "addition" >> {
    val table = 
      "a" | "b" | "result" |
       1  !  2  !    3     |
       2  !  3  !    5     |
       5  !  5  !   10     |> { (a, b, expected) =>
        a + b mustEqual expected
      }
  }
}
```

## Debugging

specs2 supports debugging individual tests:

```lua
require('neotest').run.run({ strategy = 'dap' })
```

See [[Debugging]] for setup instructions.

## Test Matching

neotest-scala uses custom matching logic for specs2:

```lua
-- Test ID normalization handles specs2's naming:
-- "test should::be awesome" → "test.should.be.awesome"
```

The adapter strips `should::`, `must::` prefixes and converts `::` to `.` for matching.

## Known Limitations

1. **Single Test Execution**: Running individual tests is limited. Tests with brackets or grouped tests may not run in isolation.

2. **String-based Specifications**: The `s2"""` string interpolation style is **not supported** due to Treesitter limitations. Use the mutable `Specification` style instead.

   ```scala
   // NOT supported (string-based)
   override def is = s2"""
     This is a test $e1
   """
   def e1 = 1 mustEqual 1

   // Supported (mutable style)
   "This is a test" in {
     1 mustEqual 1
   }
   ```

## Related Pages

- [[Supported Test Libraries|3.-Supported-Test-Libraries]] — All libraries overview
- [[Debugging]] — Debugging setup
- [[Configuration|2.-Configuration]] — Configuration options
