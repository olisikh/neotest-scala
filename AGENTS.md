# AGENTS.md - neotest-scala

## Project Overview

Neovim adapter for [neotest](https://github.com/rcarriga/neotest) that runs Scala tests. Supports: ScalaTest, munit, specs2, utest, zio-test. Integrates with nvim-metals for project metadata.

**Dependencies**: `neotest`, `nvim-nio`, `nvim-metals` (Scala LSP), `sbt` or `bloop`.

---

## Build & Test Commands

### Run All Tests
```bash
make test
```

### Run Single Test File
```bash
# Via makefile
make test-utils        # tests/utils_spec.lua
make test-junit        # tests/junit_spec.lua
make test-framework    # tests/framework/*_spec.lua
make test-integration  # tests/integration/*

# Direct plenary command
nvim --headless --clean -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/utils_spec.lua {minimal_init = 'tests/minimal_init.lua'}"
```

### Run Specific Test Pattern
```bash
nvim --headless --clean -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/framework/scalatest_spec.lua {minimal_init = 'tests/minimal_init.lua'}"
```

### Format Code
```bash
stylua lua/neotest-scala/
stylua --check lua/neotest-scala/  # verify only
```

---

## Project Structure

```
lua/neotest-scala/
├── init.lua           # Main adapter (neotest interface)
├── framework.lua      # Framework registry + global constants
├── metals.lua         # Metals LSP integration
├── build.lua          # sbt/bloop command building
├── utils.lua          # Helpers (package detection, tree utils)
├── junit.lua          # JUnit XML parsing (treesitter)
├── strategy.lua       # DAP strategy config
├── results.lua        # Test result collection
└── framework/         # Framework-specific handlers
    ├── scalatest/init.lua
    ├── munit/init.lua
    ├── specs2/
    │   ├── init.lua       # MutableSpec handling
    │   └── textspec.lua   # TextSpec handling
    ├── utest/init.lua
    └── zio-test/init.lua

tests/
├── minimal_init.lua   # Test environment setup
├── helpers/init.lua   # Test utilities (mocking, buffers)
├── framework_spec.lua
├── utils_spec.lua
├── junit_spec.lua
├── framework/         # Per-framework tests
└── integration/       # Integration tests
```

---

## Code Style

### Formatting (stylua.toml)
- 2-space indentation
- Double quotes preferred (`AutoPreferDouble`)
- Unix line endings (LF)

### Imports
```lua
local lib = require("neotest.lib")
local fw = require("neotest-scala.framework")
local utils = require("neotest-scala.utils")
local build = require("neotest-scala.build")
```

### Naming
- Files: `camelCase.lua` (e.g., `textspec.lua`)
- Functions: `snake_case` for module exports, `camelCase` for local helpers
- Constants: `UPPER_SNAKE_CASE` (e.g., `TEST_PASSED`)

### Type Annotations
```lua
---@param file_path string
---@return boolean
function adapter.is_test_file(file_path)

---@class neotest-scala.Framework
---@field name string
---@field build_command fun(root_path: string, project: string, tree: neotest.Tree, name: string, extra_args: table|string): string[]
---@field match_test nil|fun(junit_test: table<string, string>, position: neotest.Position): boolean
---@field build_test_result nil|fun(junit_test: table<string, string>, position: neotest.Position): table
---@field discover_positions nil|fun(style: string, path: string, content: string, opts: table): neotest.Tree
---@field detect_style nil|fun(content: string): string|nil
```

### Error Handling
```lua
local success, result = pcall(some_function, args)
if not success then
    vim.print("[neotest-scala] Error: " .. result)
    return {}
end
```

---

## Framework Interface

Each framework module in `lua/neotest-scala/framework/<name>/init.lua` must implement:

```lua
local M = { name = "framework-name" }

-- Required: Detect style from file content
function M.detect_style(content) -> string|nil

-- Required: Discover test positions
function M.discover_positions(style, path, content) -> neotest.Tree

-- Required: Build sbt/bloop command
function M.build_command(root_path, project, tree, name, extra_args) -> string[]

-- Optional: Match JUnit result to position (default: ID comparison)
function M.match_test(junit_test, position) -> boolean

-- Optional: Build result with errors (default: generic parsing)
function M.build_test_result(junit_test, position) -> table

-- Optional: Build namespace for JUnit lookup
function M.build_namespace(ns_node, report_prefix, node) -> table

return M
```

### Adding a New Framework
1. Create `lua/neotest-scala/framework/mylib/init.lua` with interface above
2. Register in `framework.lua:get_framework_class()`
3. Add JAR detection pattern in `metals.lua:get_framework()`
4. Create tests in `tests/framework/mylib_spec.lua`
5. Add Scala test project in `test/mylib/`

---

## Key Patterns

### Delegation Pattern
Core modules delegate framework-specific logic to framework modules:
- `init.lua` → `framework.discover_positions()`, `framework.build_command()`
- `results.lua` → `framework.build_namespace()`, `framework.match_test()`

**Never import framework-specific code directly in core files.**

### Treesitter Queries
```lua
local query = [[
  (call_expression
    function: (call_expression
      function: (identifier) @func_name (#eq? @func_name "test")
      arguments: (arguments (string) @test.name))
  ) @test.definition
]]
```
- Nested `call_expression` for `test("name")` syntax
- Use `#eq?` and `#any-of?` predicates

### Position IDs
```lua
-- Dot-separated: package.NamespaceClass.TestName
position_id = utils.build_position_id
```
Must match JUnit report test IDs for result matching.

### Test Mocking
```lua
local H = require("tests.helpers")
H.mock_fn("neotest-scala.build", "command", function() return {} end)
-- ... test code ...
H.restore_mocks()
```

---

## Known Limitations

- **specs2**: Single test execution limited; some tests run full spec
- **utest**: No `sbt.testing.TestSelector`; cannot debug individual tests
- Test ID matching may fail for names with `.`, `-`, spaces
