# neotest-scala

[Neotest](https://github.com/rcarriga/neotest) adapter for scala.

Supports the following Scala testing libraries:

- [utest](https://github.com/com-lihaoyi/utest)
- [munit](https://scalameta.org/munit/docs/getting-started.html)
- [scalatest](https://www.scalatest.org/)
- [specs2](https://etorreborre.github.io/specs2)

Runs tests with [bloop](https://scalacenter.github.io/bloop/) or [sbt](https://www.scala-sbt.org). \
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

If you are using both Bloop an SBT in your projects, you may want to dynamically specify `args`:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-scala")({
      args = function(opts)
        local my_args = {}

        if opts.runner == "sbt" then
          -- example: don't add ANSI colors in SBT
          table.insert(my_args,  "--no-colors")
        elseif opts.runner == "bloop" then
          -- example: don't add ANSI colors if using bloop, bloop expects '--no-color' argument
          table.insert(my_args, "--no-color")
        end

        if opts.path == "/my/absolute/path" then
          -- path is the folder where build.sbt resides
        end

        if opts.framework == "specs2" then
          -- framework value can be 'munit', 'utest', 'scalatest', 'specs2'
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
- [ ] Display errors in diagnostics (only specs2 is supported for now)
- [ ] Don't block neovim when trying to figure out the project name for building test commands
