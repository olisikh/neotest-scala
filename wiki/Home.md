# neotest-scala Wiki

Welcome to the neotest-scala documentation.

## Quick Links

- [[Installation|1.-Installation]] — Setup with lazy.nvim, packer, or manual
- [[Configuration|2.-Configuration]] — Args, dynamic configuration, and options
- [[Supported Test Libraries|3.-Supported-Test-Libraries]] — Overview of all 5 supported libraries
- [[ScalaTest]] — FunSuite, FreeSpec, AnyFlatSpec patterns
- [[munit]] — ScalaTest-style syntax with munit
- [[specs2]] — Mutable Specification patterns
- [[utest]] — Lightweight testing with utest
- [[zio-test]] — ZIO's built-in testing framework
- [[Debugging]] — nvim-dap integration with Metals
- [[Troubleshooting]] — Common issues and solutions
- [[Contributing]] — How to add support for new test libraries

## What This Plugin Does

A [Neotest](https://github.com/rcarriga/neotest) adapter for running Scala tests directly from Neovim.

### Features

- **5 Test Libraries Supported**: ScalaTest, munit, specs2, utest, zio-test
- **Treesitter-based Test Discovery**: Automatically detects tests in your Scala files
- **Metals Integration**: Uses nvim-metals for project metadata and build target detection
- **Debugging Support**: Debug tests with nvim-dap integration
- **Flexible Configuration**: Custom args, dynamic configuration callbacks

### Supported Test Libraries

| Library | Style | Single Test Debug |
|---------|-------|-------------------|
| [ScalaTest](ScalaTest) | BDD, FunSuite, FreeSpec | ✅ Yes |
| [munit](munit) | ScalaTest-style | ✅ Yes |
| [specs2](specs2) | Specification-based | ✅ Yes |
| [utest](utest) | Lightweight | ❌ No |
| [zio-test](zio-test) | ZIO effects | ✅ Yes |

### Quick Example

```lua
require("neotest").setup({
  adapters = {
    require("neotest-scala")
  }
})
```

Then use Neotest commands to run tests:

```vim
:Neotest run        " Run nearest test
:Neotest run file   " Run all tests in file
:Neotest summary    " Open test summary
```

## Requirements

| Requirement | Purpose |
|-------------|---------|
| **Neovim 0.8+** | Core editor |
| **neotest** | Test runner framework |
| **nvim-metals** | Scala LSP for project metadata |
| **sbt** | Build tool for running tests |
| **Treesitter Scala** | Test discovery |

See [[Installation|1.-Installation]] for detailed setup instructions.

## Fork Notice

This is a fork of the original [neotest-scala](https://github.com/stevanmilic/neotest-scala) by [Stevan Milic](https://github.com/stevanmilic). Huge thanks for creating and maintaining the original plugin.
