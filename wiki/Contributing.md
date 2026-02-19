# Contributing

Contributions to neotest-scala are welcome! This page covers how to add support for new test libraries or improve existing support.

## Development Setup

### 1. Clone and Setup

```bash
git clone https://github.com/olisikh/neotest-scala.git
cd neotest-scala
```

### 2. Project Structure

```
neotest-scala/
├── lua/neotest-scala/
│   ├── init.lua           # Main adapter implementation
│   ├── framework.lua      # Test library registry
│   ├── utils.lua          # Utility functions
│   ├── junit.lua          # JUnit XML parsing
│   └── framework/         # Test library implementations
│       ├── scalatest.lua
│       ├── munit.lua
│       ├── specs2.lua
│       ├── utest.lua
│       └── zio-test.lua
├── test/                  # Test projects for each library
│   ├── scalatest/
│   ├── munit/
│   ├── specs2/
│   ├── utest/
│   └── zio-test/
└── wiki/                  # Documentation
```

---

## Adding a New Test Library

### Step 1: Create the Framework Module

Create `lua/neotest-scala/framework/mylibrary.lua`:

```lua
local utils = require("neotest-scala.utils")

---@class neotest-scala.Framework
local M = {}

--- Builds the sbt command for running tests.
--- @param project string The sbt project name
--- @param tree neotest.Tree The test tree
--- @param name string The test name
--- @param extra_args table|string Additional arguments
--- @return string[]
function M.build_command(project, tree, name, extra_args)
  local test_namespace = utils.build_test_namespace(tree)
  
  if not test_namespace then
    return vim.tbl_flatten({ "sbt", extra_args, project .. "/test" })
  end
  
  local test_path = ""
  if tree:data().type == "test" then
    -- Customize for your library's single test syntax
    test_path = ' -- -z "' .. name .. '"'
  end
  
  return vim.tbl_flatten({ 
    "sbt", 
    extra_args, 
    project .. "/testOnly " .. test_namespace .. test_path 
  })
end

-- Optional: Custom test result matching
--- @param junit_test table<string, string>
--- @param position neotest.Position
--- @return boolean
function M.match_test(junit_test, position)
  -- Default matching logic, or implement custom
  return false
end

-- Optional: Custom result building
--- @param junit_test table<string, string>
--- @param position neotest.Position
--- @return table<string, any>
function M.build_test_result(junit_test, position)
  return {
    status = junit_test.error_message and TEST_FAILED or TEST_PASSED,
    errors = junit_test.error_message and {{ message = junit_test.error_message }} or nil,
  }
end

return M
```

### Step 2: Register in framework.lua

Add to `lua/neotest-scala/framework.lua`:

```lua
function M.get_framework_class(framework)
  -- ... existing entries ...
  elseif framework == "mylibrary" then
    return require(prefix .. "mylibrary")
  end
end
```

### Step 3: Add Detection in utils.lua

Update `utils.get_framework()` to detect your library:

```lua
function M.get_framework(build_target_info)
  -- ... existing detection ...
  or jar:match("(mylibrary)_.*-.*%.jar")
  -- ...
end
```

### Step 4: Add Treesitter Query (if needed)

If your library uses different test syntax, update `init.lua`:

```lua
function adapter.discover_positions(path)
  local query = [[
    -- ... existing patterns ...
    
    ;; mylibrary patterns
    (call_expression
      function: (identifier) @func_name (#eq? @func_name "mytest")
      arguments: (arguments (string) @test.name)
    ) @test.definition
  ]]
  -- ...
end
```

### Step 5: Create Test Project

Add a test project in `test/mylibrary/`:

```
test/mylibrary/
├── build.sbt
├── project/
│   └── build.properties
└── src/test/scala/com/example/
    └── MyLibraryTest.scala
```

### Step 6: Add Documentation

Create `wiki/mylibrary.md` with usage examples.

---

## Framework Interface

The `Framework` interface requires:

| Method | Required | Description |
|--------|----------|-------------|
| `build_command(project, tree, name, extra_args)` | ✅ | Build the sbt command |
| `match_test(junit_test, position)` | ❌ | Custom test matching |
| `build_test_result(junit_test, position)` | ❌ | Custom result building |

---

## Testing Your Changes

### Manual Testing

1. Start Neovim in a test project
2. Ensure Metals is running
3. Open a test file
4. Run `:Neotest summary` to see discovered tests
5. Run `:Neotest run` to execute tests

### Test with Different Scenarios

- [ ] Single test execution
- [ ] File-level test execution
- [ ] Directory-level test execution
- [ ] Nested test structures
- [ ] Failing tests (check error reporting)
- [ ] Debugging with `strategy = 'dap'`

---

## Code Style

- Follow Lua conventions
- Use 2-space indentation
- Add type annotations with `---@param` and `---@return`
- Keep functions small and focused

---

## Pull Request Process

1. **Fork and branch**: Create a feature branch from `main`
2. **Make changes**: Follow the guidelines above
3. **Test thoroughly**: Use the test projects
4. **Update docs**: Add or update wiki pages
5. **Submit PR**: Describe what you changed and why

### PR Checklist

- [ ] Code follows project style
- [ ] Changes are tested
- [ ] Documentation is updated
- [ ] Commit messages are descriptive

---

## Useful Commands

### Treesitter Inspection

```vim
" Show the AST for the current file
:InspectTree

" Show captures for the current query
:EditQuery
```

### Debugging the Adapter

```lua
-- Print discovered positions
:lua print(vim.inspect(require("neotest-scala").discover_positions("path/to/Test.scala")))

-- Print build target info
:lua print(vim.inspect(require("neotest-scala.utils").get_build_target_info("/project/root", "/path/to/Test.scala")))
```

---

## Related Pages

- [[Supported Test Libraries|3.-Supported-Test-Libraries]] — Existing library docs
- [[Debugging]] — Debug setup for testing
- [[Troubleshooting]] — Common issues
