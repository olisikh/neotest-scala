# Troubleshooting

Common issues and solutions when using neotest-scala.

## Quick Diagnostics

```vim
" Check if Metals is running
:LspInfo

" Check if neotest-scala is loaded
:lua print(vim.inspect(package.loaded['neotest-scala']))

" Check Treesitter parser
:TSInstallInfo

" Check test discovery
:Neotest summary
```

---

## Common Issues

### "Can't resolve root project folder"

**Symptoms**: Error when running tests

**Cause**: No `build.sbt` file found in parent directories

**Solution**: 
- Ensure you're in an sbt project with a `build.sbt` file
- Run tests from within the project directory

---

### "Can't resolve project, has Metals initialised?"

**Symptoms**: Error when trying to run tests

**Cause**: Metals LSP is not running or not yet initialized

**Solution**:
1. Wait for Metals to initialize (check `:LspInfo`)
2. If Metals isn't attached, start it manually:
   ```lua
   require("metals").initialize_or_attach({})
   ```
3. Try again after Metals shows "ready" status

---

### "Failed to detect testing library"

**Symptoms**: Plugin can't determine which test library is in use

**Cause**: Metals hasn't returned build target info, or no known test library in classpath

**Solution**:
1. Ensure your test library is added to `build.sbt`:
   ```scala
   libraryDependencies += "org.scalatest" %% "scalatest" % "3.2.18" % Test
   ```
2. Run `sbt update` to download dependencies
3. Restart Metals with `:MetalsRestartServer`
4. Try again

---

### Tests Not Discovered

**Symptoms**: No tests appear in Neotest summary

**Causes and Solutions**:

1. **File not named as test file**
   - Files must contain `test`, `spec`, or `suite` (case-insensitive)
   - Rename: `MyTests.scala` ✓, `MyClass.scala` ✗

2. **Treesitter parser not installed**
   ```vim
   :TSInstall scala
   ```

3. **Test syntax not recognized**
   - Check that your test syntax matches supported patterns
   - See [[Supported Test Libraries|3.-Supported-Test-Libraries]] for syntax details

4. **Compilation errors**
   - Tests with compilation errors won't be discovered
   - Fix compilation issues first

---

### Tests Run But Results Don't Show

**Symptoms**: Tests execute but Neotest shows no results

**Causes and Solutions**:

1. **JUnit report not found**
   - Check that `target/test-reports/` directory exists after running tests
   - Some test configurations may not generate JUnit XML

2. **Test ID mismatch**
   - Test names with special characters may not match
   - Try running the test file instead of individual tests

3. **Compilation failed**
   - Check the test output for compilation errors
   ```vim
   :Neotest output-panel
   ```

---

### Debug Not Working

**Symptoms**: `strategy = 'dap'` doesn't start debugger

**Causes and Solutions**:

1. **nvim-dap not configured**
   - Ensure nvim-dap is installed and configured
   - See [[Debugging]] for setup instructions

2. **Metals debug not enabled**
   - Ensure Metals is properly configured with debug support

3. **utest single test debugging**
   - utest doesn't support single test debugging
   - Debug at the suite level instead

---

### "Compilation failed" Error

**Symptoms**: Tests show compilation failure

**Solutions**:
1. Run `sbt compile` to see detailed errors
2. Fix compilation errors in your test code
3. Check for missing dependencies in `build.sbt`

---

### Slow Test Discovery

**Symptoms**: Long delay before tests appear

**Causes and Solutions**:

1. **Large project**
   - Metals needs time to index large projects
   - Wait for indexing to complete

2. **Slow Metals startup**
   - First run after `sbt clean` is slower
   - Subsequent runs are faster with BSP caching

---

### Wrong Project Running

**Symptoms**: Tests run in wrong sbt subproject

**Cause**: neotest-scala can't determine which project the file belongs to

**Solution**:
1. Ensure Metals has indexed all subprojects
2. Check that source paths are correctly configured in `build.sbt`

---

### Test Results Incorrect

**Symptoms**: Passed tests show as failed, or vice versa

**Causes and Solutions**:

1. **Test name matching issues**
   - Test names with special characters (`.`, `-`, spaces) may cause matching issues
   - This is a known limitation in some cases

2. **specs2 naming**
   - specs2 uses different naming conventions
   - The adapter normalizes names but edge cases exist

---

## Diagnostic Commands

### Check Metals Status

```vim
:MetalsStatus
:MetalsQuickRun
```

### Check Test Output

```vim
:Neotest output
:Neotest output-panel
```

### Re-run with Verbose Output

```lua
require('neotest').run.run({ extra_args = { "-v" } })
```

### Enable Plugin Logging

Add to your config for debugging:

```lua
-- Temporarily add prints to see what's happening
vim.notify = function(msg, ...) print(msg) end
```

---

## Getting Help

1. **Check existing issues**: [GitHub Issues](https://github.com/olisikh/neotest-scala/issues)
2. **Provide diagnostic info**:
   - Neovim version: `:version`
   - Metals status: `:LspInfo`
   - Test library and version from `build.sbt`
   - Minimal reproduction case

---

## Related Pages

- [[Debugging]] — Debug setup and issues
- [[Configuration|2.-Configuration]] — Configuration options
- [[Supported Test Libraries|3.-Supported-Test-Libraries]] — Library-specific notes
