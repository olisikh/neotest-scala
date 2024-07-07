# neotest-scala

## !!! DISCLAIMER

This is a fork of original [neotest-scala](https://github.com/stevanmilic/neotest-scala). \
Since the project
is unmaintained and I need to run my tests in Neovim, I have forked the repository and added support
for specs2 and zio-test libraries.

Please use it at your own risk and don't blame the author.

## About

[Neotest](https://github.com/rcarriga/neotest) adapter for Scala.

Supports the following Scala testing libraries:

- [utest](https://github.com/com-lihaoyi/utest)
- [munit](https://scalameta.org/munit/docs/getting-started.html)
- [scalatest](https://www.scalatest.org/)
- [specs2](https://etorreborre.github.io/specs2)
- [zio-test](https://zio.dev/reference/test/https://zio.dev/reference/test)

Runs tests with [sbt](https://www.scala-sbt.org). \
Relies on [nvim-metals](https://github.com/scalameta/nvim-metals) to get project metadata information

![Hero image](./img/hero.png)

## Debugging

Plugin also supports debugging tests with [nvim-dap](https://github.com/rcarriga/nvim-dap) (requires [nvim-metals](https://github.com/scalameta/nvim-metals)). \
You can debug individual test cases as well, but note that utest framework doesn't support this because it doesn't implement `sbt.testing.TestSelector`. \
To run tests with debugger pass `strategy = "dap"` when running neotest:

```lua
require('neotest').run.run({strategy = 'dap'})
```

## Requirements

- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) and the parser for scala.
- [nvim-metals](https://github.com/scalameta/nvim-metals) has no direct hard dependency,
  but relies on Metals LSP client to get metadata about the project.

## Missing features:

- diagnostics (only specs2)
- only `FunSuite` and `FreeSpec` are supported in scalatest
- only `mutable.Specification` style is supported in specs2

## Installation

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use({
  "nvim-neotest/neotest",
  requires = {
    ...,
    "stevanmilic/neotest-scala",
  }
  config = function()
    require("neotest").setup({
      ...,
      adapters = {
        require("neotest-scala"),
      }
    })
  end
})
```

## Configuration

You may override some arguments that are passed into the build tool when you are running tests:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-scala")({
      args = {"--no-color" },
    })
  }
})
```

If you want to dynamically specify `args`:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-scala")({
      args = function(opts)
        local my_args = {}

        if opts.path == "/my/absolute/path" then
          -- path is the folder where build.sbt resides
        end

        if opts.framework == "specs2" then
          -- framework value can be 'munit', 'utest', 'scalatest', 'specs2', 'zio-test'
        end

        if opts.project == "my-secret-project" then
          -- project name (build target)
        end

        return my_args
      end,
    })
  }
})
```

## Roadmap

To be implemented:

- [x] Detect test library
- [x] Detect build tool that is being used
- [ ] Display errors in diagnostics (only specs2 and zio-test are supported for now)
- [ ] Don't block neovim when trying to figure out the project name for building test commands
