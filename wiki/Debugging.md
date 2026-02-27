# Debugging

neotest-scala supports debugging tests with [nvim-dap](https://github.com/mfussenegger/nvim-dap) and [nvim-metals](https://github.com/scalameta/nvim-metals).

## Requirements

| Requirement | Purpose |
|-------------|---------|
| **nvim-dap** | Debug Adapter Protocol client for Neovim |
| **nvim-metals** | Scala LSP with debug capabilities |
| **Java Debug Server** | Metals handles this automatically |

## Setup

### 1. Install nvim-dap

```lua
-- lazy.nvim
{
  'mfussenegger/nvim-dap',
  dependencies = {
    'rcarriga/nvim-dap-ui',  -- Optional: nice UI for debugging
  },
}
```

### 2. Configure nvim-metals with DAP

```lua
local metals_config = require('metals').bare_config()

-- Auto-attach Metals
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "scala", "sbt" },
  callback = function()
    require("metals").initialize_or_attach(metals_config)
    require("metals").setup_dap()
  end,
  group = vim.api.nvim_create_augroup("nvim-metals", { clear = true }),
})
```

### 3. Configure nvim-dap for Scala

```lua
local dap = require('dap')

-- Scala/Java debug configuration
dap.configurations.scala = {
  {
    type = "scala",
    request = "launch",
    name = "Run or Test Target",
    metals = {
      runType = "runOrTestFile",
    },
  },
}
```

## Running Tests with Debugger

### Basic Debug Run

```lua
-- Debug nearest test
require('neotest').run.run({ strategy = 'dap' })

-- Debug all tests in file
require('neotest').run.run({ vim.fn.expand('%'), strategy = 'dap' })
```

### Keymaps Example

```lua
vim.keymap.set('n', '<leader>td', function()
  require('neotest').run.run({ strategy = 'dap' })
end, { desc = "Debug nearest test" })
```

### Using Command Mode

```vim
:lua require('neotest').run.run({strategy = 'dap'})
```

## Current Behavior and Limits

DAP support prioritizes reliable session startup:

1. **Nearest test runs at file scope**
   - Test-node debug requests launch `runType = "testFile"`.
2. **Per-test DAP selectors are disabled**
   - This applies to all frameworks, including ScalaTest, munit, specs2, utest, and zio-test.
3. **No-suite runs are failed**
   - `No test suites were run.` is reported as a failed run, including DAP.
4. **Metals controls backend execution**
   - neotest-scala cannot force Metals DAP to pick sbt/bloop at debug-launch time.

## How It Works

When you run a test with the `dap` strategy, neotest-scala:

1. **Queries Metals** for build target information
2. **Builds a debug configuration** appropriate for the test type:
   - **File**: Uses `runType = "testFile"`
   - **Namespace/Class**: Uses `testClass` parameter
   - **Individual Test**: Uses file-level debug (`runType = "testFile"`)

3. **Starts the debugger** via nvim-dap

## Debug Configuration by Test Type

### File Level

```lua
{
  type = "scala",
  request = "launch",
  name = "Run Test",
  metals = {
    runType = "testFile",
    path = "file:///path/to/TestFile.scala",
  },
}
```

### Class/Namespace Level

```lua
{
  type = "scala",
  request = "launch",
  name = "from_lens",
  metals = {
    testClass = "com.example.MyTestSuite",
  },
}
```

### Individual Test

```lua
{
  type = "scala",
  request = "launch",
  name = "Run Test",
  metals = {
    runType = "testFile",
    path = "file:///path/to/TestFile.scala",
  },
}
```

### Fallback (Unsafe/Unsupported Test Selection)

```lua
{
  type = "scala",
  request = "launch",
  name = "Run Test",
  metals = {
    runType = "testFile",
    path = "file:///path/to/TestFile.scala",
  },
}
```

## Debugging Support by Library

| Library | Single Test Debug | Class Debug | Notes |
|---------|-------------------|-------------|-------|
| ScalaTest | ❌ | ✅ | Nearest-test debug runs file scope |
| munit | ❌ | ✅ | Nearest-test debug runs file scope |
| specs2 | ❌ | ✅ | Nearest-test debug runs file scope |
| utest | ❌ | ✅ | Nearest-test debug runs file scope |
| zio-test | ❌ | ✅ | Nearest-test debug runs file scope |

### Per-Test Limitation

Individual test debugging is intentionally disabled in DAP mode. You can:

1. Debug the entire test suite
2. Temporarily isolate the test you want to debug
3. Add breakpoints that catch the right test

## Using with nvim-dap-ui

For a better debugging experience:

```lua
require("dapui").setup()

-- Auto-open UI on debug
vim.api.nvim_create_autocmd("FileType", {
  pattern = "scala",
  callback = function()
    local dap = require('dap')
    local dapui = require('dapui')
    
    dap.listeners.after.event_initialized["dapui_config"] = function()
      dapui.open()
    end
    dap.listeners.before.event_terminated["dapui_config"] = function()
      dapui.close()
    end
    dap.listeners.before.event_exited["dapui_config"] = function()
      dapui.close()
    end
  end,
})
```

## Troubleshooting Debug Issues

### "No debug adapter found"

Ensure Metals is running and has initialized:

```vim
:LspInfo
" Should show metals attached
```

### "Cannot find main class"

The test may not have compiled. Run tests normally first:

```vim
:Neotest run
```

### Breakpoints Not Hit

1. Ensure the code is compiled with debug symbols (default in sbt)
2. Check that the breakpoint is in the correct file
3. Try setting the breakpoint after the debug session starts

### utest: Can't Debug Individual Tests

This is a known limitation. Debug at the suite level instead.

## Related Pages

- [[Troubleshooting]] — General issues
- [[Configuration|2.-Configuration]] — Configuration options
- [[Supported Test Libraries|3.-Supported-Test-Libraries]] — Library support matrix
