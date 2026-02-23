# neotest-scala

![Hero image](./img/hero.png)

## !!! DISCLAIMER

This is a fork of original [neotest-scala](https://github.com/stevanmilic/neotest-scala), huge thanks to [Stevan Milic](https://github.com/stevanmilic) for making and maintaining this plugin.

Please use it at your own risk, any improvement proposals and contributions are welcome.

## About

[Neotest](https://github.com/rcarriga/neotest) adapter for Scala.

Supports the following Scala testing libraries:

- [utest](https://github.com/com-lihaoyi/utest)
- [munit](https://scalameta.org/munit/docs/getting-started.html)
- [scalatest](https://www.scalatest.org/)
- [specs2](https://etorreborre.github.io/specs2)
- [zio-test](https://zio.dev/reference/test/https://zio.dev/reference/test)

Runs tests with [sbt](https://www.scala-sbt.org) or [Bloop](https://scalacenter.github.io/bloop/) (faster!). \
Requires [nvim-metals](https://github.com/scalameta/nvim-metals) to get project metadata information

## Support Matrix (Current State)

Support levels below describe **test execution + result reporting** in neotest.

| Library | Test type | Build tool | Support | Notes |
|---------|-----------|------------|---------|-------|
| ScalaTest | `AnyFunSuite`, `AnyFreeSpec` | `sbt` | **Full** | Stable path via JUnit XML reports. |
| ScalaTest | `AnyFunSuite`, `AnyFreeSpec` | `bloop` | **Limited** | Can run, but report timing can lag (results may appear from previous run). |
| munit | `FunSuite` | `sbt` | **Full** | Stable path via JUnit XML reports. |
| munit | `FunSuite` | `bloop` | **Limited** | Uses stdout parsing; works for common output, but parser-based matching is inherently less stable than XML. |
| specs2 | `mutable.Specification` | `sbt` | **Limited** | General execution works, but single-test selection can still run a larger scope/spec. |
| specs2 | `mutable.Specification` | `bloop` | **Limited** | Uses stdout parsing; supports fail/crash markers, but matching remains best-effort. |
| specs2 | text spec (`s2""" ... """`) | `sbt` | **Limited** | Execution works, but fine-grained single-test runs are limited. |
| specs2 | text spec (`s2""" ... """`) | `bloop` | **Limited** | Same single-test limits plus stdout parsing constraints. |
| zio-test | `ZIOSpecDefault` | `sbt` | **Full** | Stable path via JUnit XML reports. |
| zio-test | `ZIOSpecDefault` | `bloop` | **Limited** | Parallel suite output can interleave and break reliable parsing; `@@ TestAspect.sequential` is the practical workaround. |
| uTest | `TestSuite` | `sbt` | **Full** | Works for run/result flow; debug single-test remains constrained by uTest selector limitations. |
| uTest | `TestSuite` | `bloop` | **Not supported** | Known issue: bloop may not discover/run uTest suites (`No test suites were run`). |

> Recommendation: prefer `sbt` for stability. Use `bloop` when speed matters and current framework limitations are acceptable.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
  {
    'nvim-neotest/neotest',
    dependencies = {
      'nvim-neotest/neotest-plenary',
      'olisikh/neotest-scala'
    },
  },
```

## Configuration

```lua
require("neotest").setup({
  adapters = {
    require("neotest-scala")
  }
})
```

Test library selection is automatic per file. Manual enable/disable framework options are intentionally not supported.

### Build Tool Selection

By default (`build_tool = "auto"`), the plugin follows build tool information from Metals build target metadata to stay in sync with your editor session.

Selection priority in auto mode:
- If Metals metadata clearly indicates `sbt`, use `sbt` (recommended default for stability)
- If Metals metadata clearly indicates `bloop`, use `bloop`
- If metadata is ambiguous, fall back to local detection (`.bloop/` + `bloop` executable), otherwise `sbt`

You can explicitly configure the build tool:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-scala")({
      build_tool = "bloop",  -- "auto" (default), "bloop", or "sbt"
    })
  }
})
```

**Why Bloop?** Bloop is significantly faster than sbt because:
- It keeps a running compilation server (no JVM startup overhead)
- It caches compilations incrementally
- It's already running if you use Metals

### Additional Arguments

You may override some arguments that are passed into the build tool when you are running tests:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-scala")({
      args = { "--no-colors" },
    })
  }
})
```

Also you have an option to dynamically specify `args` for SBT:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-scala")({
      args = function(args)
        -- args table contains:
        --   path - full path to the file where test is executed
        --   framework - test library name that your test is implemented with
        --   project_name - project name the test is running on
        --   build_target_info - information about the build target collected from Metals

        return { "-v" }
      end,
    })
  }
})
```

## Diagnostics

The plugin provides diagnostic information for failing tests directly in your editor:
- Error messages from test failures
- Stack trace line numbers  
- Inline error indicators via Neotest

Diagnostics are automatically displayed when tests fail, making it easy to identify and fix issues without leaving Neovim.

## Debugging

Plugin also supports debugging tests with [nvim-dap](https://github.com/rcarriga/nvim-dap) (requires [nvim-metals](https://github.com/scalameta/nvim-metals)). \
You can debug individual test cases as well, but note that utest framework doesn't support this because it doesn't implement `sbt.testing.TestSelector`. \
To run tests with debugger pass `strategy = "dap"` when running neotest:

```lua
require('neotest').run.run({strategy = 'dap'})
```
