# Implement ScalaTest Diagnostics for Failing Tests

## Context

### Problem
ScalaTest failing tests show a red cross but no diagnostic message (unlike other frameworks like munit and zio-test). The issue is that `scalatest.lua` doesn't implement the `build_test_result` function, so it falls back to the default handler which may not properly extract and format failure messages.

### Analysis
- JUnit XML reports contain failure messages in `<failure message="...">` attribute
- Stacktraces are in the failure element content
- Other frameworks (munit, zio-test, specs2) already implement `build_test_result`
- ScalaTest only has `match_test` but no custom result building

### Files to Modify
1. `lua/neotest-scala/framework/scalatest.lua` - Add `build_test_result` function

---

## Work Objectives

### Core Objective
Implement the `build_test_result` function in `scalatest.lua` to properly extract diagnostic messages and line numbers from JUnit XML for failing tests, matching the behavior of other frameworks.

### Concrete Deliverables
- Updated `lua/neotest-scala/framework/scalatest.lua` with `build_test_result` function
- Function properly extracts `error_message` from JUnit test results
- Function extracts line number from stacktrace matching the test file
- Function returns properly formatted result table with status and errors

### Definition of Done
- [ ] `build_test_result` function added to scalatest.lua
- [ ] Function extracts error_message when present
- [ ] Function extracts line number from stacktrace
- [ ] Function returns TEST_FAILED with error details when test fails
- [ ] Function returns TEST_PASSED when no error
- [ ] Tested with actual failing ScalaTest tests showing diagnostics

### Must Have
- Implementation matching pattern from munit.lua and zio-test.lua
- Proper line number extraction from stacktrace
- Error message extraction from both error_message and error_stacktrace fields

### Must NOT Have
- Changes to other framework files
- Changes to init.lua or junit.lua
- Breaking changes to existing match_test function

---

## Implementation Details

### Code Pattern to Follow
Based on munit.lua and zio-test.lua:

```lua
function M.build_test_result(junit_test, position)
    local result = {}
    local error = {}
    local file_name = utils.get_file_name(position.path)
    
    if junit_test.error_message then
        error.message = junit_test.error_message
        -- extract line from stacktrace
    elseif junit_test.error_stacktrace then
        -- extract message from first line and line from stacktrace
    end
    
    if error.message then
        result = { status = TEST_FAILED, errors = { error } }
    else
        result = { status = TEST_PASSED }
    end
    
    return result
end
```

### Line Number Extraction Pattern
```lua
local line_num = string.match(junit_test.error_stacktrace, "%(" .. file_name .. ":(%d+)%)")
if line_num then
    error.line = tonumber(line_num) - 1  -- 0-indexed for neovim
end
```

---

## Task Flow

```
Task 1 (Implementation) → Task 2 (Testing) → Task 3 (Commit) → Task 4 (Push & PR)
```

---

## TODOs

- [ ] 1. Implement build_test_result in scalatest.lua

  **What to do**:
  - Read the current scalatest.lua file
  - Add the build_test_result function after match_test function
  - Function should:
    1. Create empty result and error tables
    2. Get file_name from position.path using utils.get_file_name
    3. If junit_test.error_message exists:
       - Set error.message = junit_test.error_message
       - Try to extract line number from error_stacktrace using pattern match
    4. Else if only error_stacktrace exists (no error_message):
       - Split stacktrace by newline and use first line as error.message
       - Try to extract line number from error_stacktrace
    5. If error.message exists, return {status=TEST_FAILED, errors={error}}
    6. Else return {status=TEST_PASSED}
  
  **Code to add** (append before `return M`):
  ```lua
  ---Build test result with diagnostic message for failed tests
  ---@param junit_test table<string, string>
  ---@param position neotest.Position
  ---@return table
  function M.build_test_result(junit_test, position)
      local result = {}
      local error = {}

      local file_name = utils.get_file_name(position.path)

      -- Extract error message and line number
      if junit_test.error_message then
          error.message = junit_test.error_message

          -- Try to find line number in stacktrace
          if junit_test.error_stacktrace then
              local line_num = string.match(junit_test.error_stacktrace, "%(" .. file_name .. ":(%d+)%)")
              if line_num then
                  error.line = tonumber(line_num) - 1
              end
          end
      elseif junit_test.error_stacktrace then
          -- If no error_message but has stacktrace, extract first line as message
          local lines = vim.split(junit_test.error_stacktrace, "\n")
          error.message = lines[1]

          local line_num = string.match(junit_test.error_stacktrace, "%(" .. file_name .. ":(%d+)%)")
          if line_num then
              error.line = tonumber(line_num) - 1
          end
      end

      if error.message then
          result = {
              status = TEST_FAILED,
              errors = { error },
          }
      else
          result = {
              status = TEST_PASSED,
          }
      end

      return result
  end
  ```

  **Parallelizable**: NO

  **References**:
  - Pattern: `lua/neotest-scala/framework/munit.lua:43-66` - munit's build_test_result implementation
  - Pattern: `lua/neotest-scala/framework/zio-test.lua:16-58` - zio-test's build_test_result implementation
  - Current: `lua/neotest-scala/framework/scalatest.lua:1-30` - scalatest.lua current state

  **Acceptance Criteria**:
  - [ ] build_test_result function added to scalatest.lua
  - [ ] Function signature matches pattern: function M.build_test_result(junit_test, position)
  - [ ] Function extracts error_message when available
  - [ ] Function extracts line number from stacktrace using pattern: "%(" .. file_name .. ":(%d+)%)")
  - [ ] Function returns {status=TEST_FAILED, errors={error}} when message exists
  - [ ] Function returns {status=TEST_PASSED} when no message
  - [ ] Code follows Lua style conventions (2-space indent, double quotes)

  **Evidence**:
  - [ ] Read back scalatest.lua and verify function is present
  - [ ] Check no syntax errors with stylua if available: `stylua --check lua/neotest-scala/framework/scalatest.lua`

  **Commit**: YES (as part of Task 3)
  - Message: `feat(scalatest): add diagnostic support for failing tests`
  - Files: `lua/neotest-scala/framework/scalatest.lua`

---

- [ ] 2. Test the implementation with failing tests

  **What to do**:
  - Navigate to test-project/scalatest directory
  - Run sbt tests to generate JUnit reports: `sbt test`
  - Verify that FunSuiteSpec has failing tests (1 shouldEqual 2)
  - Open Neovim in the test project
  - Open a ScalaTest file (e.g., FunSuiteSpec.scala)
  - Run a failing test using neotest
  - Verify that diagnostic message appears ("1 did not equal 2")
  - Test both assertion failures and exceptions

  **Test Cases**:
  1. Assertion failure: `(1 shouldEqual 2)` should show "1 did not equal 2"
  2. Exception: `throw new RuntimeException("boom")` should show exception message

  **Parallelizable**: NO (depends on Task 1)

  **Acceptance Criteria**:
  - [ ] Can run ScalaTest tests through neotest
  - [ ] Failing tests show diagnostic message in neovim
  - [ ] Line numbers are correct (point to assertion line)
  - [ ] Both assertion failures and exceptions show diagnostics

  **Evidence**:
  - [ ] Screenshot or description showing diagnostic message in neovim
  - [ ] Confirm test file path: test-project/scalatest/src/test/scala/com/example/FunSuiteSpec.scala

  **Commit**: NO (testing only, no new files)

---

- [ ] 3. Commit the changes

  **What to do**:
  - Stage scalatest.lua changes: `git add lua/neotest-scala/framework/scalatest.lua`
  - Create commit with semantic message following repo style
  - Add Sisyphus attribution in commit body

  **Commit Message**:
  ```
  feat(scalatest): add diagnostic support for failing tests
  
  Implement build_test_result function to extract failure messages
  and line numbers from JUnit XML reports. This enables neotest
  to display diagnostic information (e.g., "1 did not equal 2")
  when ScalaTest assertions fail.
  
  Previously, failing tests only showed a red cross without any
  diagnostic message. Now they display the actual failure reason
  and line number, matching behavior of munit and zio-test.
  
  Ultraworked with [Sisyphus](https://github.com/code-yeongyu/oh-my-opencode)
  Co-authored-by: Sisyphus <clio-agent@sisyphuslabs.ai>
  ```

  **Parallelizable**: NO (depends on Task 1)

  **Acceptance Criteria**:
  - [ ] Commit created with proper message
  - [ ] Only scalatest.lua is committed
  - [ ] Commit includes Sisyphus attribution

  **Evidence**:
  - [ ] `git log -1` shows the commit
  - [ ] `git show --stat` shows only scalatest.lua changed

  **Commit**: YES (this is the commit task)

---

- [ ] 4. Push to current branch and create PR

  **What to do**:
  - Get current branch name: `git branch --show-current`
  - Push commits: `git push origin <branch-name>`
  - Create PR using gh CLI
  - PR title: "feat: Add diagnostic support for ScalaTest failing tests"
  - PR body should explain the change

  **PR Body Template**:
  ```markdown
  ## Summary
  
  This PR adds diagnostic message support for failing ScalaTest tests.
  
  ## Problem
  
  Previously, when a ScalaTest test failed (e.g., `1 shouldEqual 2`),
  neotest would show a red cross but no diagnostic message explaining
  what went wrong. This was inconsistent with other frameworks like
  munit and zio-test which properly display failure messages.
  
  ## Solution
  
  Implemented `build_test_result` function in `scalatest.lua` that:
  - Extracts failure messages from JUnit XML (`error_message` field)
  - Extracts line numbers from stacktraces
  - Returns properly formatted result with status and errors
  
  ## Testing
  
  Tested with `FunSuiteSpec.scala` containing:
  - Assertion failures: `(1 shouldEqual 2)` → shows "1 did not equal 2"
  - Exceptions: `throw new RuntimeException("boom")` → shows exception
  
  ## Files Changed
  
  - `lua/neotest-scala/framework/scalatest.lua` - Added `build_test_result` function
  ```

  **Parallelizable**: NO (depends on Task 3)

  **Acceptance Criteria**:
  - [ ] Changes pushed to origin
  - [ ] PR created with proper title and description
  - [ ] PR links to this feature implementation

  **Evidence**:
  - [ ] `git log origin/<branch-name>` shows commits
  - [ ] PR URL is generated and accessible

  **Commit**: NO (this is push/PR task)

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|------------|
| 3 | `feat(scalatest): add diagnostic support for failing tests` | `lua/neotest-scala/framework/scalatest.lua` | git show --stat |

---

## Success Criteria

### Verification Commands
```bash
# Verify function was added
grep -A 40 "function M.build_test_result" lua/neotest-scala/framework/scalatest.lua

# Verify no syntax errors
stylua --check lua/neotest-scala/framework/scalatest.lua 2>/dev/null || echo "stylua not available"

# Verify commit exists
git log -1 --oneline

# Verify push succeeded
git log origin/$(git branch --show-current) --oneline -1
```

### Final Checklist
- [ ] build_test_result function implemented
- [ ] Function extracts error messages
- [ ] Function extracts line numbers
- [ ] Tests show diagnostic messages
- [ ] Commit created with proper message
- [ ] Changes pushed to branch
- [ ] PR created

---

## Notes

### Current State Reference
File: `lua/neotest-scala/framework/scalatest.lua`
```lua
local utils = require("neotest-scala.utils")

---@class neotest-scala.Framework
local M = {}

--- Builds a command for running tests for the framework.
---@param root_path string Project root path
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
function M.build_command(root_path, project, tree, name, extra_args)
    return utils.build_command(root_path, project, tree, name, extra_args)
end

---@param junit_test table<string, string>
---@param position neotest.Position
---@return boolean
function M.match_test(junit_test, position)
    local package_name = utils.get_package_name(position.path)
    local junit_test_id = package_name .. junit_test.namespace .. "." .. junit_test.name:gsub(" ", ".")
    local test_id = position.id:gsub(" ", ".")

    return junit_test_id == test_id
end

---@return neotest-scala.Framework
return M
```

### JUnit XML Format Reference
From test-project/scalatest/target/test-reports/TEST-com.example.FunSuiteSpec.xml:
```xml
<testcase classname="com.example.FunSuiteSpec" name="failing test" time="0.006">
  <failure message="1 did not equal 2" type="org.scalatest.exceptions.TestFailedException">
    org.scalatest.exceptions.TestFailedException: 1 did not equal 2
    at ... (FunSuiteSpec.scala:12)
    ...
  </failure>
</testcase>
```

The `message` attribute contains the diagnostic ("1 did not equal 2").
The stacktrace contains the line number in format `(FileName.scala:12)`.
