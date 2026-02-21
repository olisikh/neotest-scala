# Work Plan: Refactor discover_positions for Framework-Specific Discovery

## Context

Current `discover_positions` uses a generic treesitter query matching ALL frameworks. It discovers tests without checking if the library is in classpath.

**Goal**: Each framework module implements its own `discover_positions`, checking classpath first.

**Branch**: `feature/framework-aware-discovery`

---

## TODOs

- [ ] 1. Create branch `feature/framework-aware-discovery`
- [ ] 2. Add `metals.get_frameworks()` - returns array of all frameworks in classpath
- [ ] 3. Add `discover_positions(style, path, content, opts)` to scalatest module
- [ ] 4. Add `discover_positions(style, path, content, opts)` to munit module
- [ ] 5. Add `discover_positions(style, path, content, opts)` to specs2 module (inc. TextSpec)
- [ ] 6. Add `discover_positions(style, path, content, opts)` to utest module
- [ ] 7. Add `discover_positions(style, path, content, opts)` to zio-test module
- [ ] 8. Refactor `init.discover_positions` to orchestrate framework discovery
- [ ] 9. Add integration tests for multi-framework scenarios
- [ ] 10. Create PR

---

## Task Details

### Task 2: metals.get_frameworks()

**File**: `lua/neotest-scala/metals.lua`

Add function:
```lua
function M.get_frameworks(root_path, target_path)
  -- Parse classpath, return array like { "scalatest", "munit" }
end
```

**Test**: Create `tests/metals_frameworks_spec.lua`

---

### Task 3: scalatest discover_positions

**File**: `lua/neotest-scala/framework/scalatest/init.lua`

Add:
```lua
local STYLE_PATTERNS = {
  funsuite = "extends.*AnyFunSuite",
  freespec = "extends.*AnyFreeSpec",
}

function M.detect_style(content)
  -- Check extends clause
end

function M.discover_positions(style, path, content, opts)
  -- Return neotest.Tree
end
```

**Test**: `tests/framework/scalatest/discovery_spec.lua`

---

### Task 4-7: Other frameworks

Same pattern as Task 3. Each framework:
- `detect_style(content)` - checks extends clause
- `discover_positions(style, path, content, opts)` - returns Tree

---

### Task 8: init.lua refactor

**File**: `lua/neotest-scala/init.lua`

New `discover_positions`:
```lua
function adapter.discover_positions(path)
  local content = lib.files.read(path)
  local root = adapter.root(path)
  
  local frameworks = metals.get_frameworks(root, path)
  if not frameworks or #frameworks == 0 then
    return {}  -- empty tree
  end
  
  local trees = {}
  for _, fw_name in ipairs(frameworks) do
    local fw = require("neotest-scala.framework." .. fw_name:gsub("-", "-"))
    if fw.discover_positions then
      local style = fw.detect_style and fw.detect_style(content) or "default"
      local tree = fw.discover_positions(style, path, content, {})
      if tree then table.insert(trees, tree) end
    end
  end
  
  return merge_trees(trees)  -- dedupe by position
end
```

Remove:
- Generic treesitter query (lines 77-97)
- TextSpec special case (lines 73-75)

---

## Acceptance Criteria

- [ ] All 114 tests pass
- [ ] Test IDs remain unchanged
- [ ] Files with no framework in classpath return empty tree
- [ ] Multi-framework files discover tests from all frameworks
- [ ] PR created on `feature/framework-aware-discovery`

---

## Commit Order

1. `feat(metals): add get_frameworks()`
2. `feat(scalatest): add discover_positions`
3. `feat(munit): add discover_positions`
4. `feat(specs2): add discover_positions`
5. `feat(utest): add discover_positions`
6. `feat(zio-test): add discover_positions`
7. `refactor(init): orchestrate framework-aware discovery`
8. `test: add integration tests`
