# AGENTS.md - Project Documentation

## 1. Project Overview

`neotest-scala` is a Neovim adapter for [neotest](https://github.com/rcarriga/neotest) that enables running Scala tests directly from Neovim. It supports multiple Scala test libraries (ScalaTest, munit, specs2, utest, zio-test) and integrates with nvim-metals for project metadata.

**Dependencies**: `neotest`, `neotest-plenary`, `nvim-metals` (Scala LSP), `sbt` (build tool).

---

## 2. Project Structure

```
neotest-scala/
├── lua/neotest-scala/
│   ├── init.lua           # Main adapter - neotest interface
│   ├── framework.lua      # Test library registry
│   ├── utils.lua          # Utilities (Metals integration, commands)
│   ├── junit.lua          # JUnit XML parsing for test results
│   └── framework/         # Test library-specific handlers
│       ├── scalatest.lua
│       ├── munit.lua
│       ├── specs2.lua
│       ├── utest.lua
│       └── zio-test.lua
├── test/                  # Scala test projects for each library
│   ├── build.sbt          # Root project config
│   ├── scalatest/
│   ├── munit/
│   ├── specs2/
│   ├── utest/
│   └── zio-test/
├── stylua.toml            # Lua formatting config
└── wiki/                  # Documentation (GitHub Wiki)
```

---

## 3. Architecture

### Adapter Flow

```
:Neotest run
    │
    ├─► discover_positions()     # Treesitter query to find tests
    │
    ├─► build_spec()             # Build sbt command + DAP config
    │   ├─► Metals for project info
    │   ├─► Detect test library via classpath
    │   └─► Build sbt command
    │
    └─► results()                # Parse JUnit XML output
        └─► junit.lua            # Treesitter XML parser
```

### Key Modules

| Module | Purpose |
| :--- | :--- |
| `init.lua` | Main adapter implementing neotest interface |
| `framework.lua` | Registry - maps library name to handler |
| `utils.lua` | Metals integration, package detection, command building |
| `junit.lua` | Parses JUnit XML reports via Treesitter XML parser |
| `framework/*.lua` | Library-specific command building + result matching |

---

## 4. Build & Test Commands

### Lua Code (Neovim Plugin)

**Format Code:**
```bash
stylua lua/neotest-scala/
```

**Verify Formatting:**
```bash
stylua --check lua/neotest-scala/
```

### Scala Test Projects

The plugin uses sbt to run tests. Test projects are in `test/` subdirectory.

**Run All Test Projects:**
```bash
cd test && sbt test
```

**Run Single Framework Tests:**
```bash
cd test/scalatest && sbt test
cd test/munit && sbt test
cd test/specs2 && sbt test
cd test/utest && sbt test
cd test/zio-test && sbt test
```

**Run Single Test Class:**
```bash
cd test/scalatest && sbt "testOnly com.example.FunSuiteSpec"
```

**Run Single Test:**
```bash
cd test/scalatest && sbt "testOnly com.example.FunSuiteSpec -- -z \"Hello, & ScalaTest!\""
```

### Manual Testing in Neovim

1. Open a Scala test file in one of the test projects
2. Ensure Metals is running (`:LspInfo`)
3. Run `:Neotest summary` to see discovered tests
4. Run `:Neotest run` on a test

---

## 5. Code Style Guidelines

### Formatting (stylua.toml)

```toml
line_endings = "Unix"
indent_type = "Spaces"
quote_style = "AutoPreferDouble"
```

**Rules:**
- 2-space indentation
- Double quotes preferred (AutoPreferDouble)
- Unix line endings (LF)

### Lua Conventions

**Imports:**
```lua
local lib = require("neotest.lib")
local fw = require("neotest-scala.framework")
local utils = require("neotest-scala.utils")
```

**Naming:**
- Modules: `camelCase` (e.g., `myModule.lua`)
- Functions: `camelCase` (e.g., `buildCommand`)
- Constants: `UPPER_SNAKE_CASE` (e.g., `TEST_PASSED`)
- Variables: `camelCase` or `snake_case`

**Type Annotations:**
Use LuaLS annotations for clarity:
```lua
---@param file_path string
---@return boolean
function adapter.is_test_file(file_path)
```

**Tables as Types:**
```lua
---@class neotest-scala.Framework
---@field build_command fun(project: string, tree: neotest.Tree, name: string, extra_args: table|string): string[]
---@field match_test nil|fun(junit_test: table<string, string>, position: neotest.Position): boolean
```

### Error Handling

Use `pcall` for potentially failing operations:
```lua
local success, result = pcall(some_function, args)
if not success then
    vim.print("[neotest-scala] Error: " .. result)
    return {}
end
```

### Treesitter Queries

Defined inline in `init.lua` and `junit.lua`:
```lua
local query = [[
  (call_expression
    function: (identifier) @func_name
  ) @test.definition
]]
```

- Use S-expression format
- Use `#eq?` and `#any-of?` predicates for matching
- Capture nodes with `@name` syntax

---

## 6. Test Library Interface

Each test library handler must implement:

```lua
---@class neotest-scala.Framework
local M = {}

-- Required: Build sbt command
function M.build_command(project, tree, name, extra_args)
    -- Return string[] command
end

-- Optional: Custom test matching
function M.match_test(junit_test, position)
    -- Return boolean
end

-- Optional: Custom result building
function M.build_test_result(junit_test, position)
    -- Return table with status/errors
end

return M
```

**Registry:** Add new libraries in `framework.lua`:
```lua
function M.get_framework_class(framework)
    -- ...
    elseif framework == "mylibrary" then
        return require(prefix .. "mylibrary")
    end
end
```

**Detection:** Add JAR pattern in `utils.lua`:
```lua
or jar:match("(mylibrary)_.*-.*%.jar")
```

---

## 7. Adding a New Test Library

1. Create `lua/neotest-scala/framework/mylibrary.lua` with the interface above
2. Register in `lua/neotest-scala/framework.lua`
3. Add detection in `lua/neotest-scala/utils.lua:get_framework()`
4. Add Treesitter query patterns in `init.lua:discover_positions()` if needed
5. Add test project in `test/mylibrary/`
6. Add documentation in `wiki/`

---

## 8. Known Limitations

- **specs2**: Single test execution is limited; runs full spec for some tests
- **utest**: Does not implement `sbt.testing.TestSelector`; cannot debug individual tests
- Test ID matching may fail for names with special characters (`.`, `-`, spaces)
- Framework detection relies on Metals build target info

---

## 9. Key Patterns

### Position ID Building
```lua
-- Dot-separated path from package + namespace hierarchy
local function build_position_id(position, parents)
    return table.concat(
        vim.tbl_flatten({
            vim.tbl_map(get_parent_name, parents),
            utils.get_position_name(position),
        }),
        "."
    )
end
```

### Test Matching
```lua
-- Match JUnit result to discovered test
local function match_test(namespace, junit_result, position)
    local package_name = utils.get_package_name(position.path)
    local junit_test_id = (package_name .. namespace .. "." .. junit_result.name)
    local test_id = position.id
    return junit_test_id == test_id
end
```

### Metals Integration
```lua
-- Query Metals for build target info
local response = metals.request_sync("workspace/executeCommand", params, timeout)
```
